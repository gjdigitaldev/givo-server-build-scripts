#!/bin/bash
# gen-windows-library-notices.sh LIBS_TSV SRC_DIR MANIFEST BUILD_LINE OUT_FILE
#
# the notices of the
# libraries inside one BtbN Windows FFmpeg build:
#   LIBS_TSV   the libraries, one per line: name, BtbN script, repository,
#              commit (more repository/commit pairs), configure flags — what
#              BtbN's scripts at the release tag pin (read as text by
#              btbn-libs.py; nothing of BtbN's is run)
#   SRC_DIR    the downloaded sources, one folder per library,
#              <name>@<commit12>/ holding the archive at that commit or, where
#              the host offers no archive, its license files
#   MANIFEST   url, bytes, sha256, saved-as of every download
#   BUILD_LINE the first line of the notice (the build it belongs to)
# Each entry: the library, its repository and commit, the download it came
# from with its SHA-256, then its license, copying, notice and patents files,
# unchanged. A library whose source holds none of those is listed at the end
# and makes the script exit 3 (the notice is still written).
# With RAV1E_CRATES (the crates `cargo tree -e normal --features capi --target
# <the build's Rust target>` lists for BtbN's rav1e commit), RAV1E_REGISTRY
# (the unpacked cargo registry) and RAV1E_LOCK, the Rust crates inside rav1e
# follow, written by crate-notices.sh.
set -uo pipefail
LIBS="${1:?libs tsv}"; SRC="${2:?source folder}"; MAN="${3:?manifest}"; LINE="${4:?build line}"; OUT="${5:?out file}"
missing=()
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pat='^(copying|licen[cs]e|copyright|notice|patents|unlicense|l?gpl[-_.0-9v]*)([._-][A-Za-z0-9.]+)*$'
{
  echo "$LINE"
  echo "The libraries statically linked into it, as BtbN's build scripts at that release pin them, with their"
  echo "license notices unchanged. Each entry: the library, its repository and commit, the archive we read it"
  echo "from and that archive's SHA-256; then its license files."
  while IFS=$'\t' read -r name script rest; do
    [ "$name" = sdl ] && continue
    IFS=$'\t' read -r -a f <<<"$rest"
    repo="${f[0]}"; commit="${f[1]}"
    d="$(ls -d "$SRC/$name@${commit:0:12}" 2>/dev/null | head -1)"
    echo
    echo "================================================================================"
    echo "$name — $repo @ $commit (BtbN scripts.d/$script)"
    [ -n "$d" ] || { echo "(source not downloaded)"; missing+=("$name"); continue; }
    texts=()
    files=("$d"/*)
    for a in "$d"/*-git.tar.gz; do [ -f "$a" ] && files=("$a"); done
    for a in "${files[@]}"; do
      [ -f "$a" ] || continue
      rel="${a#$SRC/}"
      row="$(awk -F'\t' -v r="$rel" '$4 ~ ("/" r "$") {print $1 " — sha256 " $3; exit}' "$MAN")"
      echo "source: ${row:-$rel}"
      case "$a" in
        *.tar.gz|*.tgz)
          rm -rf "$tmp/x"; mkdir -p "$tmp/x"
          tar -tzf "$a" 2>/dev/null > "$tmp/all"

          # files at the top and in bundled third-party folders (up to 4 levels, no
          # tests), doc/PATENTS, docs/FTL.TXT, x86inc.asm headers; googlesource
          # archives have no top folder
          top="$(head -1 "$tmp/all" | cut -d/ -f1)/"
          grep -q -v -F "$top" "$tmp/all" && top=""
          awk -v top="$top" '{ p = $0; if (top != "" && index(p, top) == 1) p = substr(p, length(top) + 1); if (p == "" || p ~ /\/$/) next
              n = split(p, c, "/"); b = tolower(c[n])
              if (tolower(p) ~ /(^|\/)(test|tests|testdata|googletest|gtest|benchmark|examples?|fuzz|\.github)(\/|$)/) next
              if (p == "doc/PATENTS" || p == "docs/FTL.TXT") { print $0; next }
              if (b == "x86inc.asm") { print "x86inc:" $0; next }
              if (n <= 4 && b ~ /^(licen[cs]e|copying|copyright|notice|patents|unlicense)/) { print $0; next }
              if (n <= 4 && b ~ /^l.*gpl.*\.txt$/) print $0 }' "$tmp/all" > "$tmp/sel"
          grep -v '^x86inc:' "$tmp/sel" > "$tmp/list" || true
          # where the license is not in such a file: the file that holds it (":head" = its first comment block)
          case "$name" in
            avisynth) extra="distrib/gpl.txt" ;;
            ffnvcodec*) extra="include/ffnvcodec/nvEncodeAPI.h:head include/ffnvcodec/dynlink_loader.h:head" ;;
            *) extra="" ;;
          esac
          for e in $extra; do
            m="$(grep -E "^${top}${e%:head}$" "$tmp/all" | head -1)"
            [ -n "$m" ] || continue
            if [ "${e%:head}" != "$e" ]; then
              tar -xzOf "$a" "$m" 2>/dev/null | awk '{print} /\*\// {exit}' > "$tmp/h.$(basename "$m")"
              texts+=("$tmp/h.$(basename "$m")|${m#$top} (its license comment)")
            else
              echo "$m" >> "$tmp/list"
            fi
          done
          if [ -s "$tmp/list" ]; then
            tar -xzf "$a" -C "$tmp/x" -T "$tmp/list" 2>/dev/null
            while read -r m; do [ -f "$tmp/x/$m" ] && { k="$tmp/t.$(echo "$m" | tr '/' '_')"; cp "$tmp/x/$m" "$k"; texts+=("$k|${m#$top}"); }; done < "$tmp/list"
          fi
          while read -r m; do
            m="${m#x86inc:}"; k="$tmp/x86.$(echo "$m" | tr '/' '_')"
            tar -xzOf "$a" "$m" 2>/dev/null | awk '/^;/ {print; next} {exit}' > "$k"
            [ -s "$k" ] && texts+=("$k|${m#$top} (its license header)")
          done < <(grep '^x86inc:' "$tmp/sel" || true) ;;
        *) b="${a##*/}"; grep -q -i -E "$pat" <<<"$b" && texts+=("$a|$b") ;;
      esac
    done
    echo "================================================================================"
    if [ "${#texts[@]}" = 0 ]; then echo "(no license file found in its source)"; missing+=("$name"); continue; fi
    for t in "${texts[@]}"; do echo; echo "--- ${t##*|} ---"; echo; cat "${t%%|*}"; done
    if [ "$name" = vmaf ]; then
      echo; echo "--- libsvm's COPYRIGHT (libvmaf's svm.cpp is libsvm 3.24) ---"; echo; cat "$(cd "$(dirname "$0")" && pwd)/notices-extra/libsvm-3.24-COPYRIGHT.txt"
    fi
  done < "$LIBS"
  if [ -n "${RAV1E_CRATES:-}" ]; then
    echo
    echo "================================================================================"
    echo "Rust crates compiled into rav1e (its library, for this build's target): $(wc -l < "$RAV1E_CRATES" | tr -d ' ')"
    echo "================================================================================"
    "$(dirname "$0")/crate-notices.sh" "$RAV1E_CRATES" "$RAV1E_REGISTRY" "$RAV1E_LOCK" "${RAV1E_TREE:-}" || missing+=("rav1e-crates")
    "$(dirname "$0")/rust-std-notice.sh" "${RUST_SRC:?RUST_SRC: the Rust library source}" "${RUST_STD_LABEL:-the Rust toolchain BtbN builds with (its version is not in BtbN's scripts; the texts are those of Rust's library source)}" || missing+=("rust-std")
  fi
  if [ "${#missing[@]}" -gt 0 ]; then
    echo
    echo "Libraries without a license file in the source read: ${missing[*]}"
  fi
} > "$OUT"
echo "wrote $OUT; without a license text: ${missing[*]:-none}"
[ "${#missing[@]}" = 0 ] || exit 3
