#!/bin/bash
# join-macos.sh — joins the two macOS slices that build-ffmpeg-macos.sh made
# (one per Mac architecture, same VARIANT) into the universal ffmpeg and
# ffprobe that package.sh bundles:
#
#   third_party/ffmpeg/join-macos.sh ARM64_OUT_DIR X86_64_OUT_DIR
#   → third_party/ffmpeg/macos/{ffmpeg,ffprobe,BUILDINFO.txt,LIBRARY-NOTICES.txt}
#
# Both slices must be FFmpeg 8.1.1 of the same variant (same license line) and
# need macOS 13.0; the result is checked to hold exactly arm64 and x86_64.
# also:
#   - the two configure lines may differ only by --enable-librav1e (the
#     x86_64 slice has no rav1e: build-ffmpeg-macos.sh's header says why);
#   - every library of the x86_64 slice's notices must be in the arm64
#     slice's (its LIBRARY-NOTICES.txt, gen-macos-library-notices.sh); the
#     universal notices are the arm64 ones, headed by the SHA-256 of each
#     slice, which third_party/licenses/gen-licenses.sh checks against the
#     binaries it ships.
set -euo pipefail
cd "$(dirname "$0")"
A="${1:?arm64 slice folder}"; X="${2:?x86_64 slice folder}"
die() { echo "join-macos: $*" >&2; exit 1; }
for d in "$A" "$X"; do for t in ffmpeg ffprobe BUILDINFO.txt LIBRARY-NOTICES.txt; do [ -f "$d/$t" ] || die "$d/$t missing"; done; done
[ "$(lipo -archs "$A/ffmpeg")" = arm64 ] || die "$A is not the arm64 slice"
[ "$(lipo -archs "$X/ffmpeg")" = x86_64 ] || die "$X is not the x86_64 slice"
va="$(sed -n 's/.*variant \([a-z]*\),.*/\1/p' "$A/BUILDINFO.txt" | head -1)"
vx="$(sed -n 's/.*variant \([a-z]*\),.*/\1/p' "$X/BUILDINFO.txt" | head -1)"
[ -n "$va" ] && [ "$va" = "$vx" ] || die "the slices are different variants ($va / $vx)"
# the configure lines, as each BUILDINFO records them
ca="$(sed -n 's/^configuration: //p' "$A/BUILDINFO.txt" | tr ' ' '\n' | grep -v '^$' | sort)"
cx="$(sed -n 's/^configuration: //p' "$X/BUILDINFO.txt" | tr ' ' '\n' | grep -v '^$' | sort)"
extra="$(comm -3 <(echo "$ca") <(echo "$cx") | tr -d '\t' | grep -v -x -e '--enable-librav1e' || true)"
[ -z "$extra" ] || die "the configure lines differ by more than --enable-librav1e: $(echo $extra)"
# the x86_64 slice's libraries are all in the arm64 notices
hdr() { LC_ALL=C grep -a -E '^[A-Za-z0-9_-]+ — .+ — source: .+ — sha256 [0-9a-f]{64}$' "$1" | sort; }
missing="$(comm -13 <(hdr "$A/LIBRARY-NOTICES.txt") <(hdr "$X/LIBRARY-NOTICES.txt"))"
[ -z "$missing" ] || die "libraries of the x86_64 slice missing from the arm64 notices: $missing"
rm -rf macos && mkdir macos
for t in ffmpeg ffprobe; do
  lipo -create "$A/$t" "$X/$t" -output "macos/$t"
  [ "$(lipo -archs "macos/$t")" = "x86_64 arm64" ] || die "macos/$t is $(lipo -archs "macos/$t")"
  chmod +x "macos/$t"
done
{ echo "== arm64 =="; cat "$A/BUILDINFO.txt"; echo "== x86_64 =="; cat "$X/BUILDINFO.txt"; } > macos/BUILDINFO.txt
{
  echo "FFmpeg 8.1.1 for macOS (ffmpeg, ffprobe; Apple silicon and Intel in one file), the slices this notice belongs to:"
  for t in ffmpeg ffprobe; do
    echo "  $t arm64  sha256 $(shasum -a 256 "$A/$t" | awk '{print $1}')"
    echo "  $t x86_64 sha256 $(shasum -a 256 "$X/$t" | awk '{print $1}')"
  done
  only="$(comm -23 <(hdr "$A/LIBRARY-NOTICES.txt") <(hdr "$X/LIBRARY-NOTICES.txt") | cut -d' ' -f1 | tr '\n' ' ')"
  [ -z "$only" ] || echo "In the Apple-silicon slice only: ${only}(and the Rust crates listed at the end, which are inside rav1e)."
  echo
  cat "$A/LIBRARY-NOTICES.txt"
} > macos/LIBRARY-NOTICES.txt
ls -l macos
