#!/bin/bash
# Builds whisper-cli (whisper.cpp) for macOS on Apple silicon with Metal, as one
# self-contained program (static libraries, the Metal shader library embedded).
#
#   whisper.cpp  v1.9.1, commit f049fff95a089aa9969deb009cdd4892b3e74916
#   Output: whisper-cli-macos   (arm64 + Metal), beside this script
#           LICENSE-whisper     (whisper.cpp's MIT license)
#
# Requires git, cmake and a recent Xcode. The build is arm64 only (Metal needs
# Apple silicon); on an Intel Mac GiVo Server makes no automatic captions.
set -euo pipefail
cd "$(dirname "$0")"

WHISPER_CPP_TAG="${WHISPER_CPP_TAG:-v1.9.1}"
WHISPER_CPP_REPO="${WHISPER_CPP_REPO:-https://github.com/ggerganov/whisper.cpp}"
# macOS 13.0, the oldest macOS GiVo Server supports; without it
# the binary needs the build Mac's macOS (101 shipped one needing 26.0).
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-13.0}"
WHISPER_CPP_COMMIT="${WHISPER_CPP_COMMIT:-f049fff95a089aa9969deb009cdd4892b3e74916}"
WORK="${WHISPER_WORK:-build-src}"
SRC="$WORK/whisper.cpp"

echo "== whisper.cpp $WHISPER_CPP_TAG (Metal, arm64, static) =="
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
WORK="$(cd "$WORK" && pwd -P)"; SRC="$WORK/whisper.cpp"
rm -rf "$SRC"
git clone --depth 1 --branch "$WHISPER_CPP_TAG" "$WHISPER_CPP_REPO" "$SRC"
MAPFLAG="-ffile-prefix-map=$WORK=/whisper-build"
[ "$(git -C "$SRC" rev-parse HEAD)" = "$WHISPER_CPP_COMMIT" ] || { echo "error: $WHISPER_CPP_TAG is not commit $WHISPER_CPP_COMMIT"; exit 1; }

# Self-contained single binary: static libs + the Metal shader library embedded
# so nothing else has to sit beside whisper-cli.
cmake -S "$SRC" -B "$SRC/build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_FLAGS="$MAPFLAG" -DCMAKE_CXX_FLAGS="$MAPFLAG" -DCMAKE_OBJC_FLAGS="$MAPFLAG" -DCMAKE_OBJCXX_FLAGS="$MAPFLAG" \
  -DBUILD_SHARED_LIBS=OFF \
  -DGGML_METAL=ON \
  -DGGML_METAL_EMBED_LIBRARY=ON \
  -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_BUILD_EXAMPLES=ON
cmake --build "$SRC/build" --config Release -j --target whisper-cli

BIN="$SRC/build/bin/whisper-cli"
[ -f "$BIN" ] || { echo "error: whisper-cli not found at $BIN (check the pinned tag's target name)"; exit 1; }
cp "$BIN" whisper-cli-macos
chmod +x whisper-cli-macos
# checks: arm64, the macOS minimum, the version, and no
# build-folder or user path inside.
[ "$(lipo -archs whisper-cli-macos)" = arm64 ] || { echo "error: whisper-cli-macos is not arm64"; exit 1; }
[ "$(vtool -show-build whisper-cli-macos | awk '/minos/ {print $2}')" = "$MACOSX_DEPLOYMENT_TARGET" ] || { echo "error: whisper-cli-macos does not target macOS $MACOSX_DEPLOYMENT_TARGET"; exit 1; }
grep -a -q -E '(^|[^0-9.])1\.9\.1([^0-9.]|$)' whisper-cli-macos || { echo "error: no 1.9.1 version string"; exit 1; }
if grep -a -q -F "$WORK" whisper-cli-macos || grep -a -q '/Users/' whisper-cli-macos; then echo "error: a build-folder or /Users/ path is inside whisper-cli-macos"; exit 1; fi
cp "$SRC/LICENSE" LICENSE-whisper

echo "== staged whisper-cli-macos ($(lipo -archs whisper-cli-macos 2>/dev/null || file -b whisper-cli-macos)) + LICENSE-whisper =="
