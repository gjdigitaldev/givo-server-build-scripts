#!/bin/bash
# crate-notices.sh CRATES_FILE REGISTRY_SRC CARGO_LOCK [OWN_TREE]
# the notice of each Rust crate in CRATES_FILE
# ("name vX.Y.Z" per line, as `cargo tree --prefix none --format '{p}'`
# prints them): its license files from the cargo registry's unpacked source,
# its Cargo.lock checksum, and for a crate without a file its Cargo.toml
# license and authors with the standard text of that license (MIT where the
# crate offers it). A crate of OWN_TREE (rav1e's own source tree, e.g. ivf)
# is covered by that project's own notice. Used by gen-macos-library-notices.sh
# and gen-windows-library-notices.sh.
set -euo pipefail
LIST="${1:?crates file}"; reg="${2:?registry src}"; LOCK="${3:?Cargo.lock}"; src="${4:-}"
while read -r name ver; do
  v="${ver#v}"; d="$reg/$name-$v"
  sum="$(awk -v n="$name" -v v="$v" '$1=="name" {cn=$3} $1=="version" {cv=$3} $1=="checksum" && cn=="\""n"\"" && cv=="\""v"\"" {gsub(/"/,"",$3); print $3}' "$LOCK")"
  echo
  if [ ! -d "$d" ]; then   # a crate of rav1e's own source tree (ivf): rav1e's license above covers it
    [ -n "$(grep -l -E "^name = \"$name\"" "$src"/*/Cargo.toml 2>/dev/null)" ] || { echo "gen-macos-library-notices: crate $name $v is neither in the registry nor in rav1e's tree" >&2; exit 1; }
    echo "--- $name $v — part of rav1e's own source tree: rav1e's license and PATENTS above ---"
    continue
  fi
  lic="$(sed -n 's/^license *= *"\(.*\)"$/\1/p' "$d/Cargo.toml" | head -1)"
  echo "--- $name $v — crates.io — license: ${lic:-see files} — Cargo.lock sha256 ${sum:-?} ---"
  files="$(cd "$d" && ls -1 | grep -i -E '^(licen[cs]e|copying|copyright|notice|unlicense)([._-][A-Za-z0-9.]+)*$' || true)"
  if [ -n "$files" ]; then
    for f in $files; do echo; echo "[$f]"; echo; cat "$d/$f"; done
  else
    authors="$(awk '/^authors *= *\[/ {on=1} on {printf "%s", $0} on && /\]/ {exit}' "$d/Cargo.toml" | sed 's/^authors *= *//')"
    echo "(no license file in the crate; its Cargo.toml: license = \"$lic\", authors = ${authors:-none listed})"
    case "$lic" in
      MIT | "MIT OR Apache-2.0" | "Apache-2.0 OR MIT" | "MIT/Apache-2.0")   # MIT chosen where the crate offers it
        echo; echo "[MIT License — the standard text, for the authors above]"; echo
        cat <<'MIT'
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
MIT
        ;;
      *) echo "gen-macos-library-notices: crate $name $v has no license file and the license '$lic' has no text here" >&2; exit 1 ;;
    esac
  fi
done < "$LIST"
