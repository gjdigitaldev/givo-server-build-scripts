#!/bin/bash
# Fetches the pinned native Windows ffmpeg.exe + ffprobe.exe for
# package-windows.sh, for x64 (ARCH=x64, the default) or ARM64 (ARCH=arm64).
#
# Source: BtbN/FFmpeg-Builds, static GPL builds of the FFmpeg master branch.
# Both arches use the same MONTH-END release (BtbN keeps the last build of
# each month for two years), so both carry the same FFmpeg commit:
#   release  autobuild-2026-06-30-13-34   (FFmpeg N-125365-g9a01c1cb6a)
#   x64      ffmpeg-N-125365-g9a01c1cb6a-win64-gpl.zip
#            sha256 52c0383c460f0ec1039088f1591921fb82e3b870b32aab8faf2ff1e5ae14bf9d
#   arm64    ffmpeg-N-125365-g9a01c1cb6a-winarm64-gpl.zip
#            sha256 f1e59d579755fbb5ecfe9cde2ec2c4a59a71ae701fa8d770c95b4db9dabcedf2
#   (each matches the release's checksums.sha256 and the GitHub asset digest)
#
# The x64 build's configuration must be the one this pin was checked against
# (the set of BtbN's x64 GPL build; CONF_X64 below, without --extra-version):
# a re-published or different zip stops here before anything is staged.
#
#   Output: third_party/ffmpeg/windows-<x64|arm64>/ffmpeg.exe, ffprobe.exe,
#           LICENSE-ffmpeg.txt (the zip's LICENSE.txt: GPL v3, the build uses
#           --enable-gpl --enable-version3)
#
# FFMPEG_ZIP=/path/to/already-downloaded.zip skips the download (the sha256
# is verified either way). Never executes the downloaded binaries.
set -euo pipefail
cd "$(dirname "$0")"

ARCH="${ARCH:-x64}"
TAG="autobuild-2026-06-30-13-34"
case "$ARCH" in
  x64)   ASSET="ffmpeg-N-125365-g9a01c1cb6a-win64-gpl.zip"
         SHA256="52c0383c460f0ec1039088f1591921fb82e3b870b32aab8faf2ff1e5ae14bf9d"
         PE_WANT='x86-64' ;;
  arm64) ASSET="ffmpeg-N-125365-g9a01c1cb6a-winarm64-gpl.zip"
         SHA256="f1e59d579755fbb5ecfe9cde2ec2c4a59a71ae701fa8d770c95b4db9dabcedf2"
         PE_WANT='Aarch64' ;;
  *) echo "error: ARCH must be x64 or arm64 (got '$ARCH')"; exit 1 ;;
esac
URL="https://github.com/BtbN/FFmpeg-Builds/releases/download/$TAG/$ASSET"
OUTDIR="windows-$ARCH"

# The configure flags of the x64 build this pin was checked against (97 flags,
# sorted, --extra-version left out; read from the binary with strings, nothing
# is run). Checked 2026-11-20 against the x64 build shipped up to server 101
# (N-124941, 2026-06-10): identical except that June 30 has --disable-whisper
# where June 10 had --enable-whisper (FFmpeg's own whisper filter, which GiVo
# Server never uses — it runs whisper-cli itself). That one change is why
# ffmpeg.exe shrinks from 204 MB to 143 MB.
CONF_X64_SHA256="682f999e8942ca5977a2f94f221b6bfee9d5a616f2b54f5571e19287562a7054"

conf_of() { # $1 exe → sorted configure flags without --extra-version
  { strings -n 30 "$1" || true; } | awk '/--prefix=.*--enable-/ && !done { print; done = 1 }' | tr ' ' '\n' | grep -E '^--' | grep -v '^--extra-version=' | LC_ALL=C sort
}

rm -rf "$OUTDIR" "$OUTDIR.tmp" && mkdir -p "$OUTDIR.tmp" "$OUTDIR"
if [ -n "${FFMPEG_ZIP:-}" ]; then
  cp "$FFMPEG_ZIP" "$OUTDIR.tmp/$ASSET"
else
  echo "== fetching $URL =="
  curl -fSL --retry 3 "$URL" -o "$OUTDIR.tmp/$ASSET"
fi
echo "$SHA256  $OUTDIR.tmp/$ASSET" | shasum -a 256 -c -
unzip -q -j "$OUTDIR.tmp/$ASSET" '*/bin/ffmpeg.exe' '*/bin/ffprobe.exe' '*/LICENSE.txt' -d "$OUTDIR.tmp/x"
for f in ffmpeg.exe ffprobe.exe; do
  file -b "$OUTDIR.tmp/x/$f" | grep -q "^PE32+ .*$PE_WANT" || { echo "error: $f is not a $PE_WANT PE: $(file -b "$OUTDIR.tmp/x/$f")"; exit 1; }
  grep -a -q 'N-125365-g9a01c1cb6a' "$OUTDIR.tmp/x/$f" || { echo "error: $f is not FFmpeg N-125365-g9a01c1cb6a"; exit 1; }
done
if [ "$ARCH" = x64 ]; then
  got="$(conf_of "$OUTDIR.tmp/x/ffmpeg.exe" | shasum -a 256 | awk '{print $1}')"
  [ "$got" = "$CONF_X64_SHA256" ] || { echo "error: the x64 build's configuration ($got) is not the one this pin was checked against ($CONF_X64_SHA256)"; conf_of "$OUTDIR.tmp/x/ffmpeg.exe"; exit 1; }
fi
cp "$OUTDIR.tmp/x/ffmpeg.exe" "$OUTDIR.tmp/x/ffprobe.exe" "$OUTDIR/"
cp "$OUTDIR.tmp/x/LICENSE.txt" "$OUTDIR/LICENSE-ffmpeg.txt"
rm -rf "$OUTDIR.tmp"
echo "== staged third_party/ffmpeg/$OUTDIR/ =="
ls -1 "$OUTDIR/"
