#!/bin/bash
# build-ffmpeg-macos.sh — builds ffmpeg + ffprobe for one macOS slice with
# Martin Riedl's public FFmpeg build script, pinned to one commit, with every
# source archive checked against a SHA-256 manifest.
#
#   script   https://git.martin-riedl.de/ffmpeg/build-script
#            commit 05581a45b70c22f8b03a3ce51c577fb6ccc64d56 (2026-05-14, FFmpeg 8.1.1)
#            run with one patch, build-script-05581a4-pins.patch (the checkout
#            must be clean before it and equal to it after)
#   sources  macos-sources.tsv (URL, SHA-256, size); served by curl-shim.sh,
#            which refuses any URL not in the manifest and every prebuilt program
#   target   macOS 13.0 or later (MACOSX_DEPLOYMENT_TARGET)
#
# Variants (VARIANT=):
#   lgpl  — the libraries GiVo Server can use: OpenSSL (https), dav1d (AV1
#           decoding), libxml2, srt, plus the font/subtitle libraries the
#           script always builds. No --enable-gpl; OpenSSL makes it
#           LGPL-3.0-or-later.
#   gpl   — the script's full set minus libbluray (the set of the
#           martin-riedl.de 8.1.1 download): adds x264/x265 (GPL) and the
#           other codec libraries. GPL-3.0-or-later.
#
# Usage:
#   VARIANT=lgpl|gpl SOURCE_CACHE=/path/to/cache [SHIM_MODE=verify|record] \
#     [SHIM_MIRROR=https://…] ./build-ffmpeg-macos.sh OUT_DIR
#   OUT_DIR      : receives ffmpeg, ffprobe and BUILDINFO.txt for this slice
#
# The build folder is always /Volumes/G-SSD/ffmpeg-macos-build (several GB: the
# script checkout, the build and its logs), and it must not exist yet. Its path
# is built into ffmpeg: the configuration line (--prefix), OpenSSL's
# OPENSSLDIR, ENGINESDIR and MODULESDIR, fontconfig's and libxml2's
# configuration paths, and srt's source file names. So the same bytes come only
# from the same path, and the path is the same on every Mac. It names no person
# and no product: a home folder would put an account name into every copy we
# ship, a stranger could not build at our path (and could not reproduce the
# bytes at theirs), and on a user's Mac whoever owns that account folder would
# own the folders where the bundled ffmpeg looks for OpenSSL's and fontconfig's
# configuration. Nor is it under /tmp, /var/tmp or the Shared folder in /Users:
# any account on a Mac can create a folder there, and with it an openssl.cnf
# that the bundled ffmpeg reads when it opens https. Under /Volumes a folder
# exists only while a volume of that name is mounted (the martin-riedl.de
# downloads are built the same way, on a volume of their own).
#   Without a drive named G-SSD, a disk image does the same (no admin rights):
#     hdiutil create -size 20g -type SPARSE -fs APFS -volname G-SSD ffmpeg-build
#     hdiutil attach ffmpeg-build.sparseimage
#   Two builds at one path with the same Xcode came out byte-identical
#   (SOURCE_DATE_EPOCH, ZERO_AR_DATE below).
#   SOURCE_CACHE : where the source archives are kept (<sha256>/<file>). It may
#                  start empty: each archive in macos-sources.tsv is downloaded
#                  once and kept only if its SHA-256 matches (SHIM_MIRROR, if set,
#                  is tried first). An archive not in the manifest stops the build.
#   SHIM_MODE=record downloads sources missing from the manifest once and adds
#   them, marked "tofu"; the default (verify) never downloads. VARIANT=gpl also
#   builds rav1e, whose Rust crates cargo fetches itself (into the build folder's
#   cargo-home), each checked against the checksum in rav1e's Cargo.lock.
#
# The script is run with one patch, build-script-05581a4-pins.patch (applied
# by git before anything runs): it pins the two inputs of the full set that
# move, x264 (the master branch, now a fixed commit) and rav1e's crates
# (cargo --locked).
#
# The slice is the architecture the script runs as: the script has no
# cross-compile option. The x86_64 slice on Apple silicon runs under Rosetta 2:
#   arch -x86_64 /bin/bash build-ffmpeg-macos.sh OUT_DIR
# what differs for that slice, and why:
#   - meson 1.12.1 needs Python 3.10 or later, and the only x86_64 Python on
#     the Mac is the system's 3.9.6; meson therefore runs under the Python it
#     is installed with (arm64) and is told the machine is x86_64
#     (platform.machine, which is all meson reads on macOS);
#   - so that compilers started by that arm64 process still build x86_64, the
#     cc/c++ commands on the build PATH pass -arch <slice> (on both slices);
#   - no rav1e (the AV1 encoder; GiVo Server never encodes AV1): Rust here
#     has the standard library for arm64 only, and adding the x86_64 one
#     (rustup target add x86_64-apple-darwin) is an install.
#
# Build-machine prerequisites: Xcode; meson on PATH (the script uses an
# installed meson when Python's virtualenv module is absent); autoconf,
# automake and libtool (brew install autoconf automake libtool); for
# VARIANT=gpl also Rust with cargo-c (rav1e). The script builds its own nasm, pkg-config,
# CMake, Ninja and every library from source.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
VARIANT="${VARIANT:-lgpl}"
SCRIPT_REPO="https://git.martin-riedl.de/ffmpeg/build-script.git"
SCRIPT_COMMIT="05581a45b70c22f8b03a3ce51c577fb6ccc64d56"
FFMPEG_VERSION="8.1.1"
MIN_MACOS="13.0"
MANIFEST="${MANIFEST:-$HERE/macos-sources.tsv}"
SOURCE_CACHE="${SOURCE_CACHE:?set SOURCE_CACHE to the source-archive cache folder}"
SHIM_MODE="${SHIM_MODE:-verify}"
die() { echo "build-ffmpeg-macos: $*" >&2; exit 1; }
[ $# = 1 ] || die "usage: build-ffmpeg-macos.sh OUT_DIR (the build folder is fixed: see the header)"
# one fixed build folder, the same on every Mac (header)
BUILD_ROOT="/Volumes/G-SSD/ffmpeg-macos-build"
WORK="$BUILD_ROOT"
OUT="$1"
[ -d "$(dirname "$BUILD_ROOT")" ] || die "$(dirname "$BUILD_ROOT") is not mounted: attach a drive or disk image named $(basename "$(dirname "$BUILD_ROOT")") (see the header)"
case "$(cd "$(dirname "$OUT")" 2>/dev/null && pwd -P)/" in "$BUILD_ROOT"/*) die "OUT_DIR may not be inside the build folder $BUILD_ROOT" ;; esac

# a work folder whose path names a user
# (it becomes ffmpeg's --prefix) or that is too shallow to be a work folder
refuse_path() { # $1 path, $2 what
  local d; d="$(cd "$(dirname "$1")" 2>/dev/null && pwd -P)/$(basename "$1")" || die "$2: $1 — its parent does not exist"
  case "$d/" in
    /Users/*|/home/*|"$HOME"/*|/private/var/root/*|/var/root/*) die "$2 is under a home folder ($d): its path would be built into ffmpeg; use a folder elsewhere, such as a build disk" ;;
  esac
  [ "$(tr -cd / <<<"${d%/}" | wc -c | tr -d ' ')" -ge 3 ] || die "$2 ($d) is too close to the disk root"
}
refuse_path "$WORK" "the build folder"

SLICE="$(uname -m)"
ROSETTA="$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)"
case "$SLICE" in
  arm64) ;;
  x86_64) ;;
  *) die "unsupported machine $SLICE" ;;
esac

case "$VARIANT" in
  lgpl) FLAGS=(-SKIP_X264=YES -SKIP_X265=YES -SKIP_X265_MULTIBIT=YES -SKIP_AOM=YES -SKIP_RAV1E=YES
               -SKIP_SVT_AV1=YES -SKIP_VVENC=YES -SKIP_VPX=YES -SKIP_LIBWEBP=YES -SKIP_OPEN_JPEG=YES
               -SKIP_OPEN_H264=YES -SKIP_LIBTHEORA=YES -SKIP_LIBVORBIS=YES -SKIP_LAME=YES -SKIP_OPUS=YES
               -SKIP_ZIMG=YES -SKIP_LIBVMAF=YES -SKIP_SNAPPY=YES -SKIP_LIBKLVANC=YES -SKIP_ZVBI=YES
               -SKIP_LIBBLURAY=YES) ;;
  gpl)  FLAGS=(-SKIP_LIBBLURAY=YES)
        [ "$SLICE" = arm64 ] || FLAGS+=(-SKIP_RAV1E=YES) ;;
  *) die "VARIANT must be lgpl or gpl (got '$VARIANT')" ;;
esac
RUST_NEEDED=0; [ "$VARIANT" = gpl ] && [ "$SLICE" = arm64 ] && RUST_NEEDED=1
FLAGS+=(-SKIP_BUNDLE=YES -SKIP_TEST=NO)

GATES_ONLY="${GATES_ONLY:-0}"   # 1: re-run only the checks below on the existing build folder
[ "$GATES_ONLY" = 1 ] || { [ -e "$WORK" ] && die "$WORK exists — move it aside or delete it first (this script deletes nothing)"; }
mkdir -p "$WORK" "$OUT" "$SOURCE_CACHE"
touch "$MANIFEST"

# --- the script, at the pinned commit, unchanged ------------------------------
if [ ! -d "$WORK/build-script/.git" ]; then
  git -c credential.helper= clone --quiet "$SCRIPT_REPO" "$WORK/build-script"
fi
git -C "$WORK/build-script" checkout --quiet "$SCRIPT_COMMIT"
[ "$(git -C "$WORK/build-script" rev-parse HEAD)" = "$SCRIPT_COMMIT" ] || die "build script is not at $SCRIPT_COMMIT"
PATCH="$HERE/build-script-05581a4-pins.patch"
if git -C "$WORK/build-script" apply --reverse --check "$PATCH" 2>/dev/null; then :
else
  [ -z "$(git -C "$WORK/build-script" status --porcelain)" ] || die "build script checkout is modified"
  git -C "$WORK/build-script" apply "$PATCH" || die "$PATCH does not apply"
fi
# the checkout is the pinned commit plus exactly this patch
[ "$(git -C "$WORK/build-script" diff)" = "$(sed -n '/^diff --git/,$p' "$PATCH")" ] \
  && [ -z "$(git -C "$WORK/build-script" status --porcelain --untracked-files=all | grep -v '^ M ')" ] || die "build script checkout differs from the commit plus $(basename "$PATCH")"
[ "$(cat "$WORK/build-script/version/ffmpeg")" = "$FFMPEG_VERSION" ] || die "the pinned script does not build FFmpeg $FFMPEG_VERSION"

# --- a closed tool PATH: the shim, the few host tools the script needs, the system
mkdir -p "$WORK/shim" "$WORK/hostbin"
cp "$HERE/curl-shim.sh" "$WORK/shim/curl"
chmod +x "$WORK/shim/curl"
link() { local p; p="$(command -v "$1" 2>/dev/null)" || die "$1 not found on PATH"; ln -sf "$p" "$WORK/hostbin/$1"; }
# meson: on arm64 the installed one; on x86_64 the
# same meson, under its own Python, told the machine is x86_64 (header)
if [ "$SLICE" = arm64 ]; then
  link meson
else
  mp="$(command -v meson)" || die "meson not found on PATH"
  mpy="$(head -1 "$mp" | sed -n 's/^#!\(.*\)$/\1/p')"                                   # its interpreter, from its first line
  [ -x "$mpy" ] || die "meson's Python ($mpy) not found"
  cat > "$WORK/hostbin/meson-$SLICE.py" <<MPY
# meson for the $SLICE slice (build-ffmpeg-macos.sh): meson reads the machine
# from platform.machine() on macOS, and this Python runs as arm64
import platform, sys
platform.machine = lambda: "$SLICE"
sys.argv[0] = __file__   # meson runs itself again through this file
from mesonbuild.mesonmain import main
sys.exit(main())
MPY
  printf '#!/bin/bash\nexec "%s" "%s" "$@"\n' "$mpy" "$WORK/hostbin/meson-$SLICE.py" > "$WORK/hostbin/meson"
  chmod +x "$WORK/hostbin/meson"
fi
# the script's prepareMeson() runs
# `python3 -m virtualenv` and then an unpinned `pip install meson`: the python3
# on the build PATH refuses virtualenv, venv, pip and ensurepip, so the script
# always takes the installed meson, whose version is checked here.
MESON_VERSION="${MESON_VERSION:-1.12.1}"
[ "$("$WORK/hostbin/meson" -v)" = "$MESON_VERSION" ] || die "meson $("$WORK/hostbin/meson" -v) is installed; this build expects $MESON_VERSION (MESON_VERSION=… to change it deliberately)"
cat > "$WORK/hostbin/python3" <<'PY'
#!/bin/bash
# build PATH python3: no virtualenv / venv / pip (no unpinned downloads); else the system python3
for a in "$@"; do case "$a" in virtualenv|venv|pip|pip3|ensurepip) echo "python3 -m $a is not allowed in this build" >&2; exit 1 ;; esac; done
exec /usr/bin/python3 "$@"
PY
chmod +x "$WORK/hostbin/python3"
# autotools: libklvanc and zimg (gpl set) run autogen.sh; libxml2, opus and
# nasm only when their archive has no configure script.
for t in aclocal autoconf autoheader autom4te autoreconf automake autoscan autoupdate ifnames glibtoolize; do link "$t"; done
lt="$(dirname "$(command -v glibtoolize)")/../opt/libtool/libexec/gnubin/libtoolize"
[ -x "$lt" ] && ln -sf "$lt" "$WORK/hostbin/libtoolize" || ln -sf "$(command -v glibtoolize)" "$WORK/hostbin/libtoolize"
if [ "$RUST_NEEDED" = 1 ]; then
  for t in cargo rustc cargo-cbuild cargo-cinstall cargo-capi cargo-ctest; do
    p="$(command -v "$t" 2>/dev/null || true)"; [ -n "$p" ] || p="$HOME/.cargo/bin/$t"
    [ -x "$p" ] || die "$t not found (VARIANT=gpl builds rav1e with cargo-c)"
    ln -sf "$p" "$WORK/hostbin/$t"
  done
fi

# CMake on Apple silicon searches /opt/homebrew (and /usr/local) by default, so
# a library from a package manager could slip into a build (openjpeg's tools
# found Homebrew's lcms2, libpng and libtiff on the first try). Every CMake run
# of the script reads this file through CMAKE_TOOLCHAIN_FILE (CMake >= 3.21
# takes it from the environment) and ignores those prefixes.
cat > "$WORK/cmake-ignore-host.cmake" <<'CMAKE'
set(CMAKE_IGNORE_PREFIX_PATH "/opt/homebrew;/usr/local;/opt/local")
set(CMAKE_SYSTEM_IGNORE_PREFIX_PATH "/opt/homebrew;/usr/local;/opt/local")
CMAKE

# Apple's current linker no longer knows -force_cpusubtype_ALL, which
# libvorbis 1.3.7's configure still adds on macOS (gpl set): cc/gcc/clang on
# the build PATH are Xcode's clang with that one flag dropped.
# and every C and C++ compiler on the build PATH
# names the slice (-arch), so a compiler started by an arm64 process (meson on
# the x86_64 slice) still builds the slice
for c in cc gcc clang; do
  printf '#!/bin/bash\n# Xcode clang for the %s slice, without -force_cpusubtype_ALL (unknown to the current linker)\na=()\nfor x in "$@"; do [ "$x" = -force_cpusubtype_ALL ] || a+=("$x"); done\nexec /usr/bin/clang -arch %s "${a[@]}"\n' "$SLICE" "$SLICE" > "$WORK/hostbin/$c"
  chmod +x "$WORK/hostbin/$c"
done
for c in c++ g++ clang++; do
  printf '#!/bin/bash\n# Xcode clang++ for the %s slice\nexec /usr/bin/clang++ -arch %s "$@"\n' "$SLICE" "$SLICE" > "$WORK/hostbin/$c"
  chmod +x "$WORK/hostbin/$c"
done

# OpenSSL writes its build date into the binary
# ("built on: …"); SOURCE_DATE_EPOCH, the pinned script commit's own date, makes
# that line the same on every run; ZERO_AR_DATE=1 keeps the static libraries'
# member dates out of them, so the linker's UUID (a hash of its inputs) is the
# same too.
SOURCE_DATE_EPOCH="$(git -C "$WORK/build-script" log -1 --format=%ct "$SCRIPT_COMMIT")"
start="$(date +%s)"
[ "$GATES_ONLY" = 1 ] || { mkdir "$WORK/build"; ( cd "$WORK/build" &&
  env -i HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" LANG=C LC_ALL=C \
      PATH="$WORK/shim:$WORK/hostbin:/usr/bin:/bin:/usr/sbin:/sbin" \
      MACOSX_DEPLOYMENT_TARGET="$MIN_MACOS" CARGO_HOME="$WORK/cargo-home" \
      SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" ZERO_AR_DATE=1 \
      CMAKE_TOOLCHAIN_FILE="$WORK/cmake-ignore-host.cmake" \
      SHIM_MANIFEST="$MANIFEST" SHIM_CACHE="$SOURCE_CACHE" SHIM_MODE="$SHIM_MODE" SHIM_LOG="$WORK/shim.log" \
      SHIM_MIRROR="${SHIM_MIRROR:-}" PIP_NO_INDEX=1 PYTHONNOUSERSITE=1 \
      /bin/bash "$WORK/build-script/build.sh" "${FLAGS[@]}" ) > "$WORK/build.log" 2>&1 \
  || { tail -20 "$WORK/build.log" >&2; die "the build script failed (logs: $WORK/build/log)"; }; }
secs=$(( $(date +%s) - start ))

# --- gates --------------------------------------------------------------------
BIN="$WORK/build/out/bin"
for t in ffmpeg ffprobe; do
  f="$BIN/$t"
  [ -x "$f" ] || die "$t was not built"
  [ "$(lipo -archs "$f")" = "$SLICE" ] || die "$t is $(lipo -archs "$f"), not $SLICE"
  minos="$(vtool -show-build "$f" | awk '/minos/ {print $2}')"
  [ "$minos" = "$MIN_MACOS" ] || die "$t needs macOS $minos, not $MIN_MACOS"
  extra="$(otool -L "$f" | sed 1d | awk '{print $1}' | grep -v -E '^(/usr/lib/|/System/Library/)' || true)"
  [ -z "$extra" ] || die "$t links libraries outside the system: $extra"
done
F="$BIN/ffmpeg"
conf="$("$F" -hide_banner -buildconf 2>&1)"
lic="$("$F" -hide_banner -L 2>&1)"
case "$VARIANT" in
  lgpl) grep -q -- '--enable-gpl' <<<"$conf" && die "lgpl build has --enable-gpl"
        grep -q 'GNU Lesser General Public License' <<<"$lic" && grep -q 'version 3' <<<"$lic" || die "lgpl build does not report LGPL v3" ;;
  gpl)  grep -q -- '--enable-gpl' <<<"$conf" || die "gpl build lacks --enable-gpl"
        grep -q 'GNU General Public License' <<<"$lic" && grep -q 'version 3' <<<"$lic" || die "gpl build does not report GPL v3" ;;
esac
need() { # $1 listing flag, rest: names that must appear as whole words
  local what="$1" list; shift
  list="$("$F" -hide_banner "$what" 2>/dev/null)"
  for n in "$@"; do grep -q -E "(^|[[:space:]])$n([[:space:]]|$)" <<<"$list" || die "ffmpeg $what lacks $n"; done
}
need -encoders h264_videotoolbox aac mjpeg pcm_s16le webvtt rawvideo wrapped_avframe
need -decoders h264 hevc mpeg2video aac ac3 eac3 mp2 mp3 libdav1d cc_dec subrip ass mov_text webvtt
need -muxers mpegts webvtt hls image2 wav null rawvideo mp4 adts
need -demuxers hls mpegts mov,mp4,m4a,3gp,3g2,mj2 matroska,webm flv concat
need -filters blackdetect silencedetect movie scale fps crop hstack split format aresample
need -devices lavfi
need -bsfs h264_mp4toannexb hevc_mp4toannexb
protos="$("$F" -hide_banner -protocols 2>/dev/null)"        # captured first: no grep -q on a pipe (pipefail)
for p in https http tcp tls crypto subfile file pipe srt rtmp udp; do   # (FFmpeg 8 has no hls: protocol; the hls demuxer is checked above)
  grep -q -x "  $p" <<<"$protos" || die "no $p protocol"
done
httphelp="$("$F" -hide_banner -h protocol=http 2>&1 || true)"
grep -q reconnect_max_retries <<<"$httphelp" || die "http protocol lacks reconnect_max_retries"
grep -q 'REFUSED unknown' "$WORK/shim.log" 2>/dev/null && die "the build asked for a source not in the manifest (see $WORK/shim.log)"
# a library or header from a package manager in any build log (the autotools
# themselves run from /opt/homebrew and print their own path: not counted)
leak="$(grep -l -E 'Found [A-Za-z0-9_]+: /(opt/homebrew|usr/local|opt/local)/|-[IL]/(opt/homebrew|usr/local)/|/(opt/homebrew|usr/local)/(lib|include)/|/opt/homebrew/opt/[^ ]*/(lib|include)' "$WORK/build/log/"*.log 2>/dev/null || true)"
[ -z "$leak" ] || die "a library from /opt/homebrew or /usr/local reached the build: $leak"
for t in ffmpeg ffprobe; do
  # (Rust's standard library, inside rav1e in the gpl set, carries its own source
  # paths from the Rust toolchain: those are not a host library)
  strings -n 6 "$BIN/$t" | grep -E '/opt/homebrew|/usr/local/(lib|include)' | grep -v -q '/rustlib/src/rust/library/' && die "$t refers to /opt/homebrew or /usr/local"
done

# the only build-machine path inside the programs is
# the fixed build folder: no home folder, no temporary folder, no other volume
for t in ffmpeg ffprobe; do
  other="$(strings -n 6 "$BIN/$t" | grep -o -E '/(Users|Volumes|private/var/folders|var/folders|private/tmp)/[^[:space:]"]*' | grep -v -F "$BUILD_ROOT/" | sort -u | head -5 || true)"
  [ -z "$other" ] || die "$t holds a build path outside $BUILD_ROOT: $other"
done

# --- result ---------------------------------------------------------------------
cp "$BIN/ffmpeg" "$BIN/ffprobe" "$OUT/"
{
  echo "ffmpeg $FFMPEG_VERSION for macOS $SLICE, variant $VARIANT, minimum macOS $MIN_MACOS"
  echo "build script $SCRIPT_REPO @ $SCRIPT_COMMIT, plus $(basename "$PATCH") sha256 $(shasum -a 256 "$PATCH" | awk '{print $1}')"
  echo "build host: $([ "$ROSETTA" = 1 ] && echo "Rosetta 2 ($SLICE on Apple silicon); meson under $(head -1 "$(command -v meson)" | cut -c3-) told the machine is $SLICE" || echo native)$([ "$VARIANT" = gpl ] && [ "$RUST_NEEDED" = 0 ] && echo "; no rav1e (no $SLICE Rust standard library)")$([ "$RUST_NEEDED" = 1 ] && echo "; $(rustc -V), cargo-c $(cargo cbuild --version 2>/dev/null | awk '{print $2}')")"
  echo "build folder $BUILD_ROOT (fixed; its path is inside the programs), $(diskutil info "$(dirname "$BUILD_ROOT")" 2>/dev/null | awk -F': *' '/File System Personality/ {print $2}')"
  echo "build time ${secs}s on $(sysctl -n machdep.cpu.brand_string), Xcode $(xcodebuild -version 2>/dev/null | head -1 | awk '{print $2}'), meson $(meson -v)"
  echo "license: $(sed -n '1,3p' <<<"$lic" | tr '\n' ' ')"
  echo "configuration: $(grep -E '^[[:space:]]+--' <<<"$conf" | tr -s ' \n' ' ')"
  echo "sources served: $(grep -c '^SERVED\|^RECORDED' "$WORK/shim.log" 2>/dev/null || echo 0) (manifest $(shasum -a 256 "$MANIFEST" | awk '{print $1}'))"
  for t in ffmpeg ffprobe; do echo "$t $(stat -f %z "$OUT/$t") bytes sha256 $(shasum -a 256 "$OUT/$t" | awk '{print $1}')"; done
} > "$OUT/BUILDINFO.txt"
cat "$OUT/BUILDINFO.txt"
