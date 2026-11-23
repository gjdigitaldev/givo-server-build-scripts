#!/bin/bash
# rust-std-notice.sh RUST_LIBRARY_SRC TOOLCHAIN — the notice of the Rust
# standard library compiled into a Rust static library (rav1e): std, core,
# alloc, compiler_builtins and the crates std vendors (addr2line, gimli, object,
# miniz_oxide, rustc-demangle, hashbrown, …), MIT OR Apache-2.0, with the
# license files those vendored crates carry.
set -euo pipefail
L="${1:?rust library source}"; T="${2:?toolchain}"
[ -d "$L/std" ] || { echo "rust-std-notice: no Rust library source in $L" >&2; exit 1; }
echo
echo "================================================================================"
echo "The Rust standard library ($T): std, core, alloc, compiler_builtins and the crates it vendors — license: MIT OR Apache-2.0, Copyright the Rust Project Developers"
echo "================================================================================"
mit="$(ls "$L"/vendor/*/LICENSE-MIT 2>/dev/null | head -1)"; apache="$(ls "$L"/vendor/*/LICENSE-APACHE 2>/dev/null | head -1)"
[ -n "$mit" ] && [ -n "$apache" ] || { echo "rust-std-notice: no MIT/Apache texts in $L/vendor" >&2; exit 1; }
echo; echo "[the MIT License, as std's own crates carry it]"; echo; cat "$mit"
echo; echo "[the Apache License 2.0]"; echo; cat "$apache"
for d in "$L"/vendor/*/; do
  n="$(basename "$d")"
  lic="$(sed -n 's/^license *= *"\(.*\)"$/\1/p' "$d/Cargo.toml" 2>/dev/null | head -1)"
  echo; echo "--- $n (vendored by std) — license: ${lic:-see files} ---"
  for f in $(cd "$d" && ls -1 | grep -i -E '^(licen[cs]e|copying|copyright|notice)' | grep -v -x -e LICENSE-APACHE); do echo; echo "[$f]"; echo; cat "$d/$f"; done
done
