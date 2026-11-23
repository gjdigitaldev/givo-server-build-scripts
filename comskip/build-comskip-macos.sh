#!/bin/bash
# build-comskip-macos.sh
#
# Reproducible build of a fully static, universal (arm64 + x86_64) comskip
# binary for macOS. The result depends ONLY on /usr/lib and /System
# libraries (verify with `otool -L comskip-macos`).
#
# Strategy:
#   1. Build a minimal DECODE-ONLY static FFmpeg (libavformat/avcodec/avutil/
#      swscale/swresample) from source per-arch, with --disable-autodetect so
#      no Homebrew/external libraries leak in.
#   2. Build static argtable2 from source per-arch.
#   3. Build comskip (autotools) per-arch against those static libs via
#      pkg-config, then `lipo` the two slices into one universal binary.
#
# Build-time prerequisites (Homebrew, build machine only — nothing from brew
# ends up linked into the final binary):
#   brew install autoconf automake libtool pkgconf nasm
#
# Usage:
#   ./build-comskip-macos.sh [WORK_DIR] [OUT_DIR]
#     WORK_DIR : scratch build dir (default: mktemp under /tmp): empty, made by this
#                script, or holding only the two source archives / a Comskip checkout
#     OUT_DIR  : where comskip-macos is written (default: this script's dir)
#
# Pinned sources:
#   comskip   github.com/erikkaashoek/Comskip @ a140b6ac8bc8f596729e9052819affc779c3b377 (V0.83+5)
#   ffmpeg    7.1.1  sha256 733984395e0dbbe5c046abda2dc49a5544e7e0e1e2366bba849222ae9e3a03b1
#   argtable2 2.13   sha256 8f77e8a7ced5301af6e22f47302fdbc3b1ff41f2b83c43c77ae5ca041771ddbf

set -euo pipefail

WORK="${1:-$(mktemp -d /tmp/comskip-build.XXXXXX)}"
OUT="${2:-$(cd "$(dirname "$0")" && pwd)}"
JOBS="$(sysctl -n hw.ncpu)"
BREW_PREFIX="$(brew --prefix)"

COMSKIP_REPO="https://github.com/erikkaashoek/Comskip.git"
COMSKIP_COMMIT="a140b6ac8bc8f596729e9052819affc779c3b377"
FFMPEG_VER="7.1.1"
FFMPEG_SHA256="733984395e0dbbe5c046abda2dc49a5544e7e0e1e2366bba849222ae9e3a03b1"
ARGTABLE_TARBALL="argtable2-13.tar.gz"
ARGTABLE_SHA256="8f77e8a7ced5301af6e22f47302fdbc3b1ff41f2b83c43c77ae5ca041771ddbf"

# macOS 13.0, the oldest macOS GiVo Server supports; without it
# the binary needs the build Mac's macOS (build 101 shipped one needing 26.0).
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-13.0}"
# source paths inside the binary read /comskip-build/…, never the build folder
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
check_work_dir "$WORK" .givo-comskip-work ffmpeg-7.1.1.tar.xz argtable2-13.tar.gz Comskip
WORK="$(cd "$WORK" && pwd -P)"
MAPFLAG="-ffile-prefix-map=$WORK=/comskip-build"

export PATH="$BREW_PREFIX/bin:$PATH"
export ACLOCAL_PATH="$BREW_PREFIX/share/aclocal${ACLOCAL_PATH:+:$ACLOCAL_PATH}"

mkdir -p "$WORK"
cd "$WORK"

log() { printf '\n==> %s\n' "$*"; }

fetch() { # url outfile sha256
    local url="$1" out="$2" sha="$3"
    if [[ ! -f "$out" ]] || ! echo "$sha  $out" | shasum -a 256 -c - >/dev/null 2>&1; then
        curl -fL --retry 3 -o "$out" "$url"
    fi
    echo "$sha  $out" | shasum -a 256 -c -
}

# ---------------------------------------------------------------- sources
log "Fetching sources into $WORK"
fetch "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VER}.tar.xz" \
      "ffmpeg-${FFMPEG_VER}.tar.xz" "$FFMPEG_SHA256"
fetch "https://downloads.sourceforge.net/project/argtable/argtable/argtable-2.13/${ARGTABLE_TARBALL}" \
      "$ARGTABLE_TARBALL" "$ARGTABLE_SHA256"

if [[ ! -d Comskip ]]; then
    git clone "$COMSKIP_REPO" Comskip
fi
git -C Comskip fetch --quiet origin "$COMSKIP_COMMIT" 2>/dev/null || true
git -C Comskip checkout --quiet "$COMSKIP_COMMIT"

rm -rf "ffmpeg-${FFMPEG_VER}" argtable2-13
tar xJf "ffmpeg-${FFMPEG_VER}.tar.xz"
tar xzf "$ARGTABLE_TARBALL"

# argtable2-13 (2011) ships config.guess/config.sub too old to know
# arm64-apple-darwin; refresh them from automake.
AUTOMAKE_SHARE="$(ls -d "$BREW_PREFIX"/share/automake-* | tail -1)"
cp "$AUTOMAKE_SHARE/config.guess" "$AUTOMAKE_SHARE/config.sub" argtable2-13/

# comskip: generate configure once (arch-independent)
log "autoreconf comskip"
(cd Comskip && autoreconf -fiv >/dev/null)

# ---------------------------------------------------------------- per-arch
build_arch() { # arch (arm64 | x86_64)
    local arch="$1"
    local host prefix
    case "$arch" in
        arm64)  host="aarch64-apple-darwin" ;;
        x86_64) host="x86_64-apple-darwin"  ;;
        *) echo "unknown arch $arch" >&2; return 1 ;;
    esac
    prefix="$WORK/deps-$arch"
    local native_arch; native_arch="$(uname -m)"

    # ---- argtable2 (static)
    log "[$arch] argtable2"
    rm -rf "at-$arch"; cp -R argtable2-13 "at-$arch"
    # -include ctype.h: argtable2 (2011) relies on implicit declarations of
    # isspace/toupper, which are hard errors on modern clang.
    (cd "at-$arch" &&
        ./configure --host="$host" --prefix="$prefix" \
            --enable-static --disable-shared \
            CC="clang" CFLAGS="-arch $arch -O2 $MAPFLAG -include ctype.h -Wno-error=implicit-function-declaration" \
            LDFLAGS="-arch $arch" \
            >/dev/null &&
        make -C src -j"$JOBS" >/dev/null &&
        make -C src install >/dev/null &&
        mkdir -p "$prefix/lib/pkgconfig" &&
        cp argtable2.pc "$prefix/lib/pkgconfig/argtable2.pc")

    # ---- ffmpeg (minimal static, decode-only, no external libs)
    log "[$arch] ffmpeg $FFMPEG_VER (minimal static decode-only)"
    rm -rf "ff-$arch"; mkdir "ff-$arch"
    local cross=()
    if [[ "$arch" != "$native_arch" ]]; then
        cross=(--enable-cross-compile --target-os=darwin --arch="$arch")
    fi
    (cd "ff-$arch" &&
        "../ffmpeg-${FFMPEG_VER}/configure" \
            --prefix="$prefix" \
            --cc=clang \
            --extra-cflags="-arch $arch $MAPFLAG" \
            --extra-ldflags="-arch $arch" \
            ${cross[@]+"${cross[@]}"} \
            --enable-static --disable-shared \
            --disable-programs --disable-doc \
            --disable-avdevice --disable-avfilter --disable-postproc \
            --disable-network \
            --disable-encoders --disable-muxers --disable-bsfs \
            --disable-devices --disable-filters \
            --disable-protocols --enable-protocol=file,pipe \
            --disable-autodetect \
            --enable-zlib \
            >/dev/null &&
        make -j"$JOBS" >/dev/null 2>&1 &&
        make install >/dev/null)

    # ---- comskip
    log "[$arch] comskip"
    rm -rf "cs-$arch"; mkdir "cs-$arch"
    (cd "cs-$arch" &&
        PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig" \
        PKG_CONFIG_PATH="" \
        ../Comskip/configure --host="$host" \
            --enable-static --disable-gui \
            CC="clang" CFLAGS="-arch $arch -O2 $MAPFLAG" LDFLAGS="-arch $arch" \
            >/dev/null &&
        make -j"$JOBS" >/dev/null)

    # sanity: slice must contain no non-system dylib references
    local bad
    bad="$(otool -L "cs-$arch/comskip" | tail -n +2 | awk '{print $1}' \
           | grep -vE '^(/usr/lib/|/System/)' || true)"
    if [[ -n "$bad" ]]; then
        echo "ERROR: non-system dylib deps in $arch slice:" >&2
        echo "$bad" >&2
        return 1
    fi
}

build_arch arm64
build_arch x86_64

# ---------------------------------------------------------------- universal
log "lipo universal binary"
lipo -create -output "$WORK/comskip-macos" \
    "$WORK/cs-arm64/comskip" "$WORK/cs-x86_64/comskip"
strip -S "$WORK/comskip-macos" 2>/dev/null || true
codesign -f -s - "$WORK/comskip-macos"

# checks: both slices, the macOS minimum, the version, and
# no build-folder or user path inside.
[[ "$(lipo -archs "$WORK/comskip-macos")" == "x86_64 arm64" ]] || { echo "error: not a universal x86_64+arm64 binary" >&2; exit 1; }
for a in x86_64 arm64; do
    m="$(vtool -arch "$a" -show-build "$WORK/comskip-macos" | awk '/minos/ {print $2}')"
    [[ "$m" == "$MACOSX_DEPLOYMENT_TARGET" ]] || { echo "error: the $a slice needs macOS $m, not $MACOSX_DEPLOYMENT_TARGET" >&2; exit 1; }
done
grep -a -q 'Comskip 0\.83\.001' "$WORK/comskip-macos" || { echo "error: no 'Comskip 0.83.001' version string" >&2; exit 1; }
if grep -a -q -F "$WORK" "$WORK/comskip-macos" || grep -a -q '/Users/' "$WORK/comskip-macos"; then
    echo "error: a build-folder or /Users/ path is inside the binary" >&2; exit 1
fi

mkdir -p "$OUT"
install -m 0755 "$WORK/comskip-macos" "$OUT/comskip-macos"

log "Result: $OUT/comskip-macos"
file "$OUT/comskip-macos"
otool -L "$OUT/comskip-macos"
"$OUT/comskip-macos" --help 2>&1 | head -5 || true
log "Done. Work dir kept at: $WORK"
