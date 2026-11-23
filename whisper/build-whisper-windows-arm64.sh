#!/bin/bash
# build-whisper-windows-arm64.sh
#
# Builds whisper-cli.exe (whisper.cpp) for Windows on ARM (ARM64) on macOS with
# llvm-mingw: one statically linked program, CPU only, WITHOUT OpenMP, so no
# DLL ships beside it (the official ARM64 release zip needs Microsoft's
# libomp140.aarch64.dll, which may not be redistributed).
#
#   whisper.cpp  v1.9.1, commit f049fff95a089aa9969deb009cdd4892b3e74916
#                (the version every other GiVo Server download carries)
#   toolchain    llvm-mingw 20261006 UCRT for macOS
#                (llvm-mingw-20261006-ucrt-macos-universal.tar.xz,
#                sha256 a7a19b11048e89372637d26279cdb7c430ed3cf8c1e224310421312bf986ebf6)
#   CPU target   armv8.2-a+dotprod: every Windows 11 ARM PC (Snapdragon 850 and
#                later); upstream's own toolchain file assumes armv8.7-a
#   threads      ggml's own thread pool (-DGGML_OPENMP=OFF)
#   linker       --no-insert-timestamp: the same input gives the same exe
#   C++ flags    -include algorithm: v1.9.1's examples/common.cpp calls
#                std::partial_sort without including <algorithm>, which newer
#                libc++ (LLVM 23 in llvm-mingw 20261006) no longer pulls in by
#                itself; -include new goes with it, because <algorithm> makes
#                libc++ announce std::hardware_destructive_interference_size,
#                which ggml then uses (declared in <new>). Compiler flags, not
#                source changes.
#
# Result: whisper-cli.exe (PE32+ ARM64) importing only Windows system DLLs and
# the UCRT api-ms-win-crt-* set, plus LICENSE-whisper (MIT). It statically
# contains llvm-mingw's runtime (mingw-w64 CRT, winpthreads, LLVM libc++,
# libunwind, compiler-rt); their notices ship in each Windows download's
# licenses\llvm-mingw-runtime.txt.
#
# Build-machine prerequisites: git, cmake (brew install cmake).
#
# Usage:
#   LLVM_MINGW_ARCHIVE=/path/to/llvm-mingw-20261006-ucrt-macos-universal.tar.xz \
#     ./build-whisper-windows-arm64.sh [WORK_DIR] [OUT_DIR]
#   LLVM_MINGW_ARCHIVE : the toolchain's release archive, checked against its SHA-256
#              and unpacked into WORK_DIR (or LLVM_MINGW = a folder this script
#              unpacked before)
#   WORK_DIR : scratch build dir (default: mktemp): empty, made by this script, or
#              holding only a whisper.cpp checkout (offline; the commit is checked)
#   OUT_DIR  : where whisper-cli.exe + LICENSE-whisper go (default: ./windows-arm64);
#              only whisper-cli.exe is replaced, and a DLL there stops the build
#
# Never runs the produced binary (this host is macOS).
set -euo pipefail

WHISPER_CPP_TAG="v1.9.1"
WHISPER_CPP_COMMIT="f049fff95a089aa9969deb009cdd4892b3e74916"
HOST=aarch64-w64-mingw32
WORK="${1:-$(mktemp -d "${TMPDIR:-/tmp}/whisper-winarm64.XXXXXX")}"
OUT="${2:-$(cd "$(dirname "$0")" && pwd)/windows-arm64}"
LLVM_MINGW_SHA256="a7a19b11048e89372637d26279cdb7c430ed3cf8c1e224310421312bf986ebf6"
command -v cmake >/dev/null || { echo "error: cmake not found" >&2; exit 1; }

# a caller-given work folder is used (and its
# own sub-folders replaced) only when it is empty, was made by this script (its
# marker file is there), or holds nothing but the pre-seeded sources; never "/",
# a home folder or anything near the disk root.
check_work_dir() { # $1 folder, $2 marker file name, $3… names a pre-seeded folder may hold
    local d="$1" m="$2" abs e n; shift 2
    mkdir -p "$d" && abs="$(cd "$d" && pwd -P)" || { echo "error: cannot use $d as a work folder" >&2; exit 1; }
    case "$abs" in /|"$HOME"|/Users|/Users/*/Desktop|/Users/*/Documents|/home|/Volumes|/private|/tmp|/private/tmp|/var) echo "error: $abs is not a work folder" >&2; exit 1 ;; esac
    n="$(printf '%s' "$abs" | tr -cd / | wc -c | tr -d ' ')"
    [ "$n" -ge 3 ] || { echo "error: $abs is too close to the disk root to be a work folder" >&2; exit 1; }
    if [ ! -e "$abs/$m" ]; then
        for e in $(ls -A "$abs"); do
            case " $* " in *" $e "*) ;; *) echo "error: $abs holds '$e' and is not a work folder this script made (no $m) — use an empty folder" >&2; exit 1 ;; esac
        done
    fi
    touch "$abs/$m"
}
check_work_dir "$WORK" .givo-whisper-work whisper.cpp
WORK="$(cd "$WORK" && pwd -P)"

# the toolchain only from its checked release
# archive (unpacked into WORK_DIR), or a folder this script unpacked before.
if [ -n "${LLVM_MINGW_ARCHIVE:-}" ]; then
  echo "$LLVM_MINGW_SHA256  $LLVM_MINGW_ARCHIVE" | shasum -a 256 -c - || { echo "error: $LLVM_MINGW_ARCHIVE is not llvm-mingw 20261006 (SHA-256)" >&2; exit 1; }
  LLVM_MINGW="$WORK/llvm-mingw-20261006-ucrt-macos-universal"
  if [ "$(cat "$LLVM_MINGW/.givo-archive-sha256" 2>/dev/null)" != "$LLVM_MINGW_SHA256" ]; then
    rm -rf "$LLVM_MINGW"
    tar -xJf "$LLVM_MINGW_ARCHIVE" -C "$WORK"
    echo "$LLVM_MINGW_SHA256" > "$LLVM_MINGW/.givo-archive-sha256"
  fi
fi
LLVM_MINGW="${LLVM_MINGW:?set LLVM_MINGW_ARCHIVE to llvm-mingw-20261006-ucrt-macos-universal.tar.xz}"
[ "$(cat "$LLVM_MINGW/.givo-archive-sha256" 2>/dev/null)" = "$LLVM_MINGW_SHA256" ] || { echo "error: $LLVM_MINGW was not unpacked from the checked archive — pass LLVM_MINGW_ARCHIVE=<the .tar.xz>" >&2; exit 1; }
OBJDUMP="$LLVM_MINGW/bin/llvm-objdump"
[ -x "$LLVM_MINGW/bin/$HOST-clang" ] || { echo "error: $HOST-clang not found under $LLVM_MINGW/bin" >&2; exit 1; }

cd "$WORK"
SRC="$WORK/whisper.cpp"
if [ ! -d "$SRC/.git" ]; then
  git clone --depth 1 --branch "$WHISPER_CPP_TAG" https://github.com/ggml-org/whisper.cpp.git "$SRC"
fi
[ "$(git -C "$SRC" rev-parse HEAD)" = "$WHISPER_CPP_COMMIT" ] || { echo "error: whisper.cpp is not at $WHISPER_CPP_COMMIT" >&2; exit 1; }
[ -z "$(git -C "$SRC" status --porcelain)" ] || { echo "error: the whisper.cpp checkout is modified" >&2; exit 1; }

MAPFLAG="-ffile-prefix-map=$WORK=/whisper-build"
cat > "$WORK/toolchain-arm64-mingw.cmake" <<EOF
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR ARM64)
set(CMAKE_C_COMPILER   "$LLVM_MINGW/bin/$HOST-clang")
set(CMAKE_CXX_COMPILER "$LLVM_MINGW/bin/$HOST-clang++")
set(CMAKE_RC_COMPILER  "$LLVM_MINGW/bin/$HOST-windres")
set(CMAKE_AR           "$LLVM_MINGW/bin/llvm-ar")
set(CMAKE_RANLIB       "$LLVM_MINGW/bin/llvm-ranlib")
set(CMAKE_FIND_ROOT_PATH "$LLVM_MINGW/$HOST")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
EOF

rm -rf "$WORK/build"
cmake -S "$SRC" -B "$WORK/build" \
  -DCMAKE_TOOLCHAIN_FILE="$WORK/toolchain-arm64-mingw.cmake" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_FLAGS="$MAPFLAG" -DCMAKE_CXX_FLAGS="$MAPFLAG -include algorithm -include new" \
  -DCMAKE_EXE_LINKER_FLAGS="-static -Wl,--no-insert-timestamp" \
  -DBUILD_SHARED_LIBS=OFF \
  -DGGML_OPENMP=OFF \
  -DGGML_NATIVE=OFF \
  -DGGML_BACKEND_DL=OFF \
  -DGGML_CPU_ARM_ARCH=armv8.2-a+dotprod \
  -DWHISPER_SDL2=OFF \
  -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_BUILD_EXAMPLES=ON \
  -DWHISPER_BUILD_SERVER=OFF
cmake --build "$WORK/build" --config Release -j "$(sysctl -n hw.ncpu)" --target whisper-cli

BIN="$(find "$WORK/build" -name whisper-cli.exe -type f | head -1)"
[ -n "$BIN" ] || { echo "error: whisper-cli.exe was not built" >&2; exit 1; }
mkdir -p "$OUT"
# only our own file is replaced; a DLL left in
# OUT_DIR (an old whisper set) would ride into the package, so it stops here.
if ls "$OUT"/*.dll >/dev/null 2>&1; then echo "error: $OUT holds DLLs from another whisper build — empty it first" >&2; exit 1; fi
rm -f "$OUT/whisper-cli.exe"
"$LLVM_MINGW/bin/$HOST-strip" -o "$OUT/whisper-cli.exe" "$BIN"
cp "$SRC/LICENSE" "$OUT/LICENSE-whisper"

# --- checks: ARM64 PE, the version, no build path, only system/UCRT imports ----
f="$OUT/whisper-cli.exe"
file -b "$f" | grep -q '^PE32+ .*Aarch64' || { echo "error: $f is not an ARM64 PE32+" >&2; exit 1; }
grep -a -q -E '(^|[^0-9.])1\.9\.1([^0-9.]|$)' "$f" || { echo "error: no 1.9.1 version string in $f" >&2; exit 1; }
if grep -a -q -F "$WORK" "$f"; then echo "error: the build folder path is inside the binary" >&2; exit 1; fi
imports="$("$OBJDUMP" -p "$f" | awk '/DLL Name/ {print $3}')"
bad="$(grep -viE '^(api-ms-win-[a-z0-9-]+|kernel32|user32|gdi32|advapi32|shell32|ole32|oleaut32|ws2_32|bcrypt|ntdll)\.dll$' <<<"$imports" || true)"
[ -z "$bad" ] || { echo "error: unexpected DLL imports (would have to ship beside it):" >&2; echo "$bad" >&2; exit 1; }
echo "== $f =="
file -b "$f"
sed 's/^/  imports /' <<<"$imports"
shasum -a 256 "$f"
