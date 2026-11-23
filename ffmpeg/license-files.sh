#!/bin/bash
# license-files.sh SOURCE_TOP — the files of one unpacked source tree whose text
# a binary notice must carry, one relative path per line:
#   - license, copying, copyright, notice and patents files at the top and in
#     bundled third-party folders up to four levels down (aom's fastfeat and
#     vector, SVT-AV1's fastfeat and safestringlib, vvenc's SIMDe, x265's
#     dynamicHDR10, mingw-w64's runtime and winpthreads texts, …), test and
#     googletest folders left out;
#   - doc/PATENTS (dav1d's AOM patent license) and docs/FTL.TXT (FreeType);
#   - "x86inc:<path>" for each x86inc.asm, whose ISC license is its header.
# Used by gen-macos-library-notices.sh and gen-windows-library-notices.sh.
set -uo pipefail
top="${1:?source top}"
cd "$top" || exit 1
find . -maxdepth 5 -type f \( -iname 'licen[cs]e*' -o -iname 'copying*' -o -iname 'copyright*' -o -iname 'notice' -o -iname 'notice.*' -o -iname 'patents*' -o -iname 'unlicense*' -o -iname 'l*gpl*.txt' \) 2>/dev/null \
  | sed 's#^\./##' \
  | grep -v -i -E '(^|/)(test|tests|testdata|googletest|gtest|benchmark|examples?|fuzz|\.github)(/|$)' \
  | awk -F/ 'NF <= 4' | sort
for f in doc/PATENTS docs/FTL.TXT; do [ -f "$f" ] && echo "$f"; done
find . -maxdepth 6 -type f -name 'x86inc.asm' 2>/dev/null | sed 's#^\./##' | grep -v -i '/test' | sort | sed 's/^/x86inc:/'
exit 0
