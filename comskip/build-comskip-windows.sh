#!/bin/bash
# build-comskip-windows.sh
#
# Reproducible cross-build of a native Windows comskip.exe (x64 or ARM64) on
# macOS with llvm-mingw. Both architectures build the SAME source pins as
# build-comskip-macos.sh:
#
#   comskip   github.com/erikkaashoek/Comskip @ a140b6ac8bc8f596729e9052819affc779c3b377 (V0.83+5)
#   ffmpeg    7.1.1  sha256 733984395e0dbbe5c046abda2dc49a5544e7e0e1e2366bba849222ae9e3a03b1
#             (minimal static DECODE-ONLY, no --enable-gpl, no external libs → LGPL-2.1+)
#   argtable2 2.13   sha256 8f77e8a7ced5301af6e22f47302fdbc3b1ff41f2b83c43c77ae5ca041771ddbf
#   zlib      1.3.2  sha256 bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16
#             (the macOS build links the system zlib; mingw has none, so it is built here)
#
# The Comskip author's own Windows download is 0.82.012 for x64 only (no
# matching public source tag, no ARM64 build), so we build both
# architectures from the public commit above.
#
# Toolchain: llvm-mingw (github.com/mstorsjo/llvm-mingw) macOS universal UCRT
# release 20261006 (llvm-mingw-20261006-ucrt-macos-universal.tar.xz,
# sha256 a7a19b11048e89372637d26279cdb7c430ed3cf8c1e224310421312bf986ebf6).
# One toolchain carries both targets (x86_64-w64-mingw32, aarch64-w64-mingw32).
#
# Result: a single statically linked comskip.exe (PE32+ x86-64 or ARM64) that
# imports only Windows system DLLs + the UCRT api-ms-win-crt-* set
# (Windows 10+). The combined binary is GPL v2 (Comskip's license, see
# LICENSE-comskip). It also contains llvm-mingw's static runtime (mingw-w64
# CRT and winpthreads, LLVM compiler-rt), whose notices ship in the licenses
# folder of every Windows download.
#
# Build-machine prerequisites: brew install autoconf automake libtool pkgconf nasm
# (nasm: FFmpeg's x86 assembly, x64 only).
#
# Usage:
#   ARCH=x64|arm64 \
#   LLVM_MINGW_ARCHIVE=/path/to/llvm-mingw-20261006-ucrt-macos-universal.tar.xz \
#     ./build-comskip-windows.sh [WORK_DIR] [OUT_DIR]
#   LLVM_MINGW_ARCHIVE : the toolchain's release archive, checked against the SHA-256
#              above and unpacked into WORK_DIR (or LLVM_MINGW = a folder this
#              script unpacked before)
#   ARCH     : x64 (default) or arm64
#   WORK_DIR : scratch build dir (default: mktemp): empty, made by this script, or
#              pre-seeded with only the three source archives / a Comskip
#              checkout (to build offline; every archive is sha256-verified).
#   OUT_DIR  : where comskip-windows-<amd64|arm64>.exe is written (default: this dir)
#
# Never runs the produced binary (this host is macOS).

set -euo pipefail

ARCH="${ARCH:-x64}"
case "$ARCH" in
  x64)   HOST=x86_64-w64-mingw32;  FF_ARCH=x86_64;  PE_WANT='x86-64';  OUT_NAME=comskip-windows-amd64.exe ;;
  arm64) HOST=aarch64-w64-mingw32; FF_ARCH=aarch64; PE_WANT='Aarch64'; OUT_NAME=comskip-windows-arm64.exe ;;
  *) echo "error: ARCH must be x64 or arm64 (got '$ARCH')" >&2; exit 1 ;;
esac

WORK="${1:-$(mktemp -d "${TMPDIR:-/tmp}/comskip-win-$ARCH.XXXXXX")}"
OUT="${2:-$(cd "$(dirname "$0")" && pwd)}"
LLVM_MINGW_SHA256="a7a19b11048e89372637d26279cdb7c430ed3cf8c1e224310421312bf986ebf6"
JOBS="$(sysctl -n hw.ncpu)"
BREW_PREFIX="$(brew --prefix)"

COMSKIP_REPO="https://github.com/erikkaashoek/Comskip.git"
COMSKIP_COMMIT="a140b6ac8bc8f596729e9052819affc779c3b377"
FFMPEG_VER="7.1.1"
FFMPEG_SHA256="733984395e0dbbe5c046abda2dc49a5544e7e0e1e2366bba849222ae9e3a03b1"
ARGTABLE_TARBALL="argtable2-13.tar.gz"
ARGTABLE_SHA256="8f77e8a7ced5301af6e22f47302fdbc3b1ff41f2b83c43c77ae5ca041771ddbf"
ZLIB_VER="1.3.2"
ZLIB_SHA256="bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16"

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
check_work_dir "$WORK" .givo-comskip-work ffmpeg-7.1.1.tar.xz argtable2-13.tar.gz zlib-1.3.2.tar.gz Comskip
WORK="$(cd "$WORK" && pwd -P)"

# the toolchain is used only from its checked
# release archive: LLVM_MINGW_ARCHIVE (verified, then unpacked into WORK_DIR),
# or LLVM_MINGW = a folder this script unpacked earlier (it carries the stamp).
if [[ -n "${LLVM_MINGW_ARCHIVE:-}" ]]; then
    echo "$LLVM_MINGW_SHA256  $LLVM_MINGW_ARCHIVE" | shasum -a 256 -c - || { echo "error: $LLVM_MINGW_ARCHIVE is not llvm-mingw 20261006 (SHA-256)" >&2; exit 1; }
    LLVM_MINGW="$WORK/llvm-mingw-20261006-ucrt-macos-universal"
    if [[ "$(cat "$LLVM_MINGW/.givo-archive-sha256" 2>/dev/null)" != "$LLVM_MINGW_SHA256" ]]; then
        rm -rf "$LLVM_MINGW"
        tar -xJf "$LLVM_MINGW_ARCHIVE" -C "$WORK"
        echo "$LLVM_MINGW_SHA256" > "$LLVM_MINGW/.givo-archive-sha256"
    fi
fi
LLVM_MINGW="${LLVM_MINGW:?set LLVM_MINGW_ARCHIVE to llvm-mingw-20261006-ucrt-macos-universal.tar.xz}"
[[ "$(cat "$LLVM_MINGW/.givo-archive-sha256" 2>/dev/null)" == "$LLVM_MINGW_SHA256" ]] || { echo "error: $LLVM_MINGW was not unpacked from the checked archive — pass LLVM_MINGW_ARCHIVE=<the .tar.xz>" >&2; exit 1; }

export PATH="$LLVM_MINGW/bin:$BREW_PREFIX/bin:$PATH"
export ACLOCAL_PATH="$BREW_PREFIX/share/aclocal${ACLOCAL_PATH:+:$ACLOCAL_PATH}"
command -v "$HOST-clang" >/dev/null || { echo "error: $HOST-clang not found under $LLVM_MINGW/bin" >&2; exit 1; }
if [[ "$ARCH" == x64 ]]; then
    command -v nasm >/dev/null || { echo "error: nasm not found (brew install nasm) — FFmpeg's x86 assembly needs it" >&2; exit 1; }
fi

cd "$WORK"
PREFIX="$WORK/deps-$ARCH"
# Source paths inside the binary (assert messages) read /comskip-build/…, never
# the build machine's folders.
MAPFLAG="-ffile-prefix-map=$WORK=/comskip-build"

log() { printf '\n==> %s\n' "$*"; }

fetch() { # url outfile sha256
    local url="$1" out="$2" sha="$3"
    if [[ ! -f "$out" ]] || ! echo "$sha  $out" | shasum -a 256 -c - >/dev/null 2>&1; then
        curl -fL --retry 3 -o "$out" "$url"
    fi
    echo "$sha  $out" | shasum -a 256 -c -
}

# ---------------------------------------------------------------- sources
log "Sources in $WORK ($ARCH)"
fetch "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VER}.tar.xz" "ffmpeg-${FFMPEG_VER}.tar.xz" "$FFMPEG_SHA256"
fetch "https://downloads.sourceforge.net/project/argtable/argtable/argtable-2.13/${ARGTABLE_TARBALL}" "$ARGTABLE_TARBALL" "$ARGTABLE_SHA256"
fetch "https://github.com/madler/zlib/releases/download/v${ZLIB_VER}/zlib-${ZLIB_VER}.tar.gz" "zlib-${ZLIB_VER}.tar.gz" "$ZLIB_SHA256"
if [[ ! -d Comskip ]]; then
    git clone "$COMSKIP_REPO" Comskip
fi
git -C Comskip fetch --quiet origin "$COMSKIP_COMMIT" 2>/dev/null || true
git -C Comskip checkout --quiet "$COMSKIP_COMMIT"
[[ "$(git -C Comskip rev-parse HEAD)" == "$COMSKIP_COMMIT" ]] || { echo "error: Comskip not at $COMSKIP_COMMIT" >&2; exit 1; }

rm -rf "ffmpeg-${FFMPEG_VER}" argtable2-13 "zlib-${ZLIB_VER}" "$PREFIX" "ff-$ARCH" "at-$ARCH" "cs-$ARCH"
tar xJf "ffmpeg-${FFMPEG_VER}.tar.xz"
tar xzf "$ARGTABLE_TARBALL"
tar xzf "zlib-${ZLIB_VER}.tar.gz"
mkdir -p "$PREFIX/include" "$PREFIX/lib/pkgconfig"

# argtable2-13 (2011) ships config.guess/config.sub too old for the mingw targets.
AUTOMAKE_SHARE="$(ls -d "$BREW_PREFIX"/share/automake-* | tail -1)"
cp "$AUTOMAKE_SHARE/config.guess" "$AUTOMAKE_SHARE/config.sub" argtable2-13/

log "autoreconf comskip"
(cd Comskip && autoreconf -fiv >/dev/null)

# ---------------------------------------------------------------- zlib (static)
log "zlib $ZLIB_VER (static)"
(cd "zlib-${ZLIB_VER}" &&
    make -f win32/Makefile.gcc PREFIX="$HOST-" CFLAGS="-O2 $MAPFLAG" libz.a >/dev/null &&
    cp libz.a "$PREFIX/lib/" &&
    cp zlib.h zconf.h "$PREFIX/include/")
cat > "$PREFIX/lib/pkgconfig/zlib.pc" <<EOF
prefix=$PREFIX
libdir=\${prefix}/lib
includedir=\${prefix}/include
Name: zlib
Description: zlib compression library
Version: $ZLIB_VER
Libs: -L\${libdir} -lz
Cflags: -I\${includedir}
EOF

# ---------------------------------------------------------------- argtable2 (static)
log "argtable2 (static)"
cp -R argtable2-13 "at-$ARCH"
# -include ctype.h: argtable2 relies on implicit isspace/toupper declarations.
(cd "at-$ARCH" &&
    ./configure --host="$HOST" --prefix="$PREFIX" \
        --enable-static --disable-shared \
        CC="$HOST-clang" AR="$HOST-ar" RANLIB="$HOST-ranlib" \
        CFLAGS="-O2 $MAPFLAG -include ctype.h -Wno-error=implicit-function-declaration -Wno-error=implicit-int" \
        >/dev/null &&
    make -C src -j"$JOBS" >/dev/null &&
    make -C src install >/dev/null &&
    cp argtable2.pc "$PREFIX/lib/pkgconfig/argtable2.pc")

# ---------------------------------------------------------------- ffmpeg (static, decode-only)
log "ffmpeg $FFMPEG_VER (minimal static decode-only, LGPL, $FF_ARCH)"
mkdir "ff-$ARCH"
(cd "ff-$ARCH" &&
    "../ffmpeg-${FFMPEG_VER}/configure" \
        --prefix="$PREFIX" \
        --enable-cross-compile --target-os=mingw32 --arch="$FF_ARCH" \
        --cross-prefix="$HOST-" --cc="$HOST-clang" --cxx="$HOST-clang++" \
        --pkg-config=pkg-config --pkg-config-flags=--static \
        --extra-cflags="-I$PREFIX/include $MAPFLAG" --extra-ldflags="-L$PREFIX/lib" \
        --enable-static --disable-shared \
        --disable-programs --disable-doc \
        --disable-avdevice --disable-avfilter --disable-postproc \
        --disable-network \
        --disable-encoders --disable-muxers --disable-bsfs \
        --disable-devices --disable-filters \
        --disable-protocols --enable-protocol=file,pipe \
        --disable-autodetect \
        --enable-zlib \
        > configure.out &&
    make -j"$JOBS" >/dev/null 2>&1 &&
    make install >/dev/null)
grep -E '^(License|threading support|ARCH|x86 assembler|External libraries)' "ff-$ARCH/configure.out" || true
if [[ "$ARCH" == x64 ]]; then
    grep -q '^x86 assembler *nasm' "ff-$ARCH/configure.out" || { echo "error: FFmpeg configured without nasm (x86 assembly off)" >&2; exit 1; }
fi
grep -q '^License: LGPL' "ff-$ARCH/configure.out" || { echo "error: the FFmpeg inside comskip must be LGPL (decode only)" >&2; exit 1; }

# ---------------------------------------------------------------- comskip
log "comskip (static, --disable-gui)"
mkdir "cs-$ARCH"
(cd "cs-$ARCH" &&
    PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig" \
    PKG_CONFIG_PATH="" \
    ../Comskip/configure --host="$HOST" \
        --enable-static --disable-gui \
        CC="$HOST-clang" CFLAGS="-O2 $MAPFLAG" LDFLAGS="-Wl,--no-insert-timestamp" \
        >/dev/null &&
    make -j"$JOBS" comskip.exe >/dev/null)

"$HOST-strip" -o "$WORK/$OUT_NAME" "cs-$ARCH/comskip.exe"

# sanity: the right PE, the version, and imports limited to Windows system DLLs + the UCRT set
file "$WORK/$OUT_NAME" | grep -q "PE32+ .*$PE_WANT" || { echo "error: not a $PE_WANT PE32+" >&2; exit 1; }
grep -a -q 'Comskip 0\.83\.001' "$WORK/$OUT_NAME" || { echo "error: no 'Comskip 0.83.001' version string" >&2; exit 1; }
if grep -a -q -F "$WORK" "$WORK/$OUT_NAME"; then echo "error: the build folder path is inside the binary" >&2; exit 1; fi
bad="$(llvm-objdump -p "$WORK/$OUT_NAME" | awk '/DLL Name/ {print $3}' \
       | grep -viE '^(api-ms-win-[a-z0-9-]+|kernel32|user32|gdi32|comdlg32|advapi32|shell32|ole32|oleaut32|ws2_32|bcrypt|msvcrt|ntdll)\.dll$' || true)"
if [[ -n "$bad" ]]; then
    echo "error: unexpected DLL imports:" >&2; echo "$bad" >&2; exit 1
fi

mkdir -p "$OUT"
install -m 0644 "$WORK/$OUT_NAME" "$OUT/$OUT_NAME"
log "Result: $OUT/$OUT_NAME"
file "$OUT/$OUT_NAME"
llvm-objdump -p "$OUT/$OUT_NAME" | awk '/DLL Name/ {print "  imports " $3}'
shasum -a 256 "$OUT/$OUT_NAME"
log "Done. Work dir kept at: $WORK"
