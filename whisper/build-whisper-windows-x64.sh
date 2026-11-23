#!/bin/bash
# build-whisper-windows-x64.sh
#
# Builds whisper-cli.exe (whisper.cpp) for Windows x64 on macOS with
# llvm-mingw, the toolchain of the ARM64 build.
# The official x64
# release zip links Microsoft's Visual C++ runtime (MSVCP140, VCRUNTIME140,
# VCRUNTIME140_1, VCOMP140), which a clean Windows does not have, so captions
# never started there. This build needs no runtime beside it.
#
#   whisper.cpp  v1.9.1, commit f049fff95a089aa9969deb009cdd4892b3e74916
#   toolchain    llvm-mingw 20261006 UCRT for macOS
#                (llvm-mingw-20261006-ucrt-macos-universal.tar.xz,
#                sha256 a7a19b11048e89372637d26279cdb7c430ed3cf8c1e224310421312bf986ebf6)
#   CPU          ggml's own run-time choice, as in the official zip: the CPU code
#                is built once per x86-64 level as ggml-cpu-<level>.dll
#                (GGML_BACKEND_DL + GGML_CPU_ALL_VARIANTS), from plain x86-64
#                (ggml-cpu-x64.dll, SSE2 only: every 64-bit PC) up to AVX-512,
#                and ggml loads the best one the CPU supports when whisper-cli
#                starts. No level is assumed, so no CPU gets an illegal
#                instruction.
#                Without the sapphirerapids level (AMX): ggml chooses by CPUID alone, and on a CPU whose
#                operating system never enabled AMX that level would be chosen
#                and fault. Such a CPU loads zen4 (AVX-512 with VBMI, VNNI and
#                BF16) instead. The official zip has no AMX level either.
#   threads      ggml's own thread pool (-DGGML_OPENMP=OFF): no VCOMP140/libomp
#   runtime      -static: llvm-mingw's runtime (mingw-w64 CRT, winpthreads, LLVM
#                libc++, libunwind, compiler-rt) is linked into each file; only
#                Windows system DLLs and the UCRT api-ms-win-crt-* set are imported
#   names        CMAKE_SHARED_{LIBRARY,MODULE}_PREFIX="": ggml-*.dll
#                (ggml's loader looks for "ggml-cpu-*.dll" on Windows; MinGW's
#                default would be "lib…")
#   linker       --no-insert-timestamp: the same input gives the same files
#   C++ flags    -include algorithm -include new, as in the ARM64 build
#
# Result in OUT_DIR: whisper-cli.exe, libwhisper.dll (whisper.cpp names its own
# library so under MinGW), ggml.dll, ggml-base.dll and 13 ggml-cpu-*.dll levels, plus
# LICENSE-whisper (MIT). The llvm-mingw runtime notices ship in each Windows
# download's licenses\llvm-mingw-runtime.txt.
#
# Build-machine prerequisites: git, cmake.
#
# Usage:
#   LLVM_MINGW_ARCHIVE=/path/to/llvm-mingw-20261006-ucrt-macos-universal.tar.xz \
#     ./build-whisper-windows-x64.sh [WORK_DIR] [OUT_DIR]
#   (or LLVM_MINGW = a folder this script, or the ARM64 one, unpacked before)
#   OUT_DIR defaults to ./windows-x64; it must be empty or hold only a previous
#   result of this script (its .givo-whisper-x64 marker)
#
# Never runs the produced binaries (this host is macOS).
set -euo pipefail

WHISPER_CPP_TAG="v1.9.1"
WHISPER_CPP_COMMIT="f049fff95a089aa9969deb009cdd4892b3e74916"
HOST=x86_64-w64-mingw32
WORK="${1:-$(mktemp -d "${TMPDIR:-/tmp}/whisper-winx64.XXXXXX")}"
OUT="${2:-$(cd "$(dirname "$0")" && pwd)/windows-x64}"
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
cat > "$WORK/toolchain-x64-mingw.cmake" <<EOF
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR AMD64)
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
  -DCMAKE_TOOLCHAIN_FILE="$WORK/toolchain-x64-mingw.cmake" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_FLAGS="$MAPFLAG" -DCMAKE_CXX_FLAGS="$MAPFLAG -include algorithm -include new" \
  -DCMAKE_EXE_LINKER_FLAGS="-static -Wl,--no-insert-timestamp" \
  -DCMAKE_SHARED_LINKER_FLAGS="-static -Wl,--no-insert-timestamp" \
  -DCMAKE_MODULE_LINKER_FLAGS="-static -Wl,--no-insert-timestamp" \
  -DCMAKE_SHARED_LIBRARY_PREFIX= -DCMAKE_SHARED_MODULE_PREFIX= -DCMAKE_IMPORT_LIBRARY_PREFIX= \
  -DBUILD_SHARED_LIBS=ON \
  -DGGML_OPENMP=OFF \
  -DGGML_NATIVE=OFF \
  -DGGML_BACKEND_DL=ON \
  -DGGML_CPU_ALL_VARIANTS=ON \
  -DWHISPER_SDL2=OFF \
  -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_BUILD_EXAMPLES=ON \
  -DWHISPER_BUILD_SERVER=OFF
cmake --build "$WORK/build" --config Release -j "$(sysctl -n hw.ncpu)" --target whisper-cli
# the ggml-cpu-<level> modules are not dependencies of whisper-cli: build each by name (not "all",
# which also builds v1.9.1's deprecation-warning examples, which do not compile here)
variants="$(cmake --build "$WORK/build" --target help | sed -n 's/^\.\.\. \(ggml-cpu-[a-z0-9_]*\)$/\1/p' | grep -v -- '-feats$' | sort -u)"
[ -n "$variants" ] || { echo "error: no ggml-cpu-* targets" >&2; exit 1; }
cmake --build "$WORK/build" --config Release -j "$(sysctl -n hw.ncpu)" --target $variants

BIN="$(find "$WORK/build" -name whisper-cli.exe -type f | head -1)"
[ -n "$BIN" ] || { echo "error: whisper-cli.exe was not built" >&2; exit 1; }
BINDIR="$(dirname "$BIN")"
# OUT_DIR holds only this script's result: an
# official whisper set (or anything else) left there would ride into the package.
mkdir -p "$OUT"
if [ -n "$(ls -A "$OUT")" ] && [ ! -e "$OUT/.givo-whisper-x64" ]; then echo "error: $OUT holds files this script did not make — empty it first" >&2; exit 1; fi
find "$OUT" -mindepth 1 -maxdepth 1 \( -name '*.dll' -o -name '*.exe' -o -name LICENSE-whisper \) -exec rm -f {} +
touch "$OUT/.givo-whisper-x64"
"$LLVM_MINGW/bin/$HOST-strip" -o "$OUT/whisper-cli.exe" "$BIN"
for d in "$BINDIR"/*.dll; do
  case "$(basename "$d")" in ggml-cpu-sapphirerapids.dll) continue ;; esac
  "$LLVM_MINGW/bin/$HOST-strip" -o "$OUT/$(basename "$d")" "$d"
done
cp "$SRC/LICENSE" "$OUT/LICENSE-whisper"

# --- checks: x64 PE, the version, the variants, no build path, only system/UCRT imports
cd "$OUT"
file -b whisper-cli.exe | grep -q '^PE32+ .*x86-64' || { echo "error: whisper-cli.exe is not an x64 PE32+" >&2; exit 1; }
[ -f libwhisper.dll ] || { echo "error: libwhisper.dll was not built" >&2; exit 1; }
grep -a -q -E '(^|[^0-9.])1\.9\.1([^0-9.]|$)' libwhisper.dll || { echo "error: no 1.9.1 version string in libwhisper.dll" >&2; exit 1; }
for v in x64 sse42 haswell zen4; do [ -f "ggml-cpu-$v.dll" ] || { echo "error: ggml-cpu-$v.dll was not built" >&2; exit 1; }; done
[ ! -e ggml-cpu-sapphirerapids.dll ] || { echo "error: the AMX level ggml-cpu-sapphirerapids.dll must not ship (it faults where the OS has not enabled AMX)" >&2; exit 1; }
own="$(ls *.dll | tr '[:upper:]' '[:lower:]')"
fail=0
for f in whisper-cli.exe *.dll; do
  if grep -a -q -F "$WORK" "$f"; then echo "error: the build folder path is inside $f" >&2; fail=1; fi
  file -b "$f" | grep -q '^PE32+ .*x86-64' || { echo "error: $f is not x64" >&2; fail=1; }
  imports="$("$OBJDUMP" -p "$f" | awk '/DLL Name/ {print $3}')"
  bad="$(grep -viE '^(api-ms-win-[a-z0-9-]+|kernel32|user32|gdi32|advapi32|shell32|ole32|oleaut32|ws2_32|bcrypt|ntdll)\.dll$' <<<"$imports" | while read -r i; do grep -qx "$(tr '[:upper:]' '[:lower:]' <<<"$i")" <<<"$own" || echo "$i"; done || true)"
  [ -z "$bad" ] || { echo "error: $f imports a DLL that is neither Windows' nor ours: $bad" >&2; fail=1; }
done
[ "$fail" = 0 ] || exit 1
echo "== $OUT =="
for f in whisper-cli.exe *.dll; do printf '%-28s %9s  %s\n' "$f" "$(stat -f %z "$f")" "$(shasum -a 256 "$f" | cut -c1-16)"; done
echo "imports outside the set: none (Windows system DLLs, api-ms-win-crt-*, and these files)"
