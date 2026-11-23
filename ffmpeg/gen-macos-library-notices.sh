#!/bin/bash
# gen-macos-library-notices.sh — the notices of the libraries built into one
# macOS FFmpeg build (build-ffmpeg-macos.sh), taken from the exact source
# archives the build used:
#
#   third_party/ffmpeg/gen-macos-library-notices.sh WORK_DIR SOURCE_CACHE OUT_FILE
#
# Which libraries count: the ones the built ffmpeg links (from its configure
# line, plus zlib, which FFmpeg finds by itself); build tools (nasm,
# pkg-config, CMake, Ninja) and libraries only ffplay uses are left out. Each
# entry is one header line (library, version, source address, archive SHA-256)
# and the archive's own license file(s), unchanged — PATENTS files included.
# also:
#   - license texts named after their license (libklvanc's lgpl-2.1.txt);
#   - the libraries known to carry a PATENTS file (aom, SVT-AV1, libvpx,
#     libwebp, rav1e) must show it, or the notices stop;
#   - with rav1e, every Rust crate compiled into its library: `cargo tree -e
#     normal` with the features cargo-c built (default + capi), proc-macro
#     crates left out (they run in the compiler, nothing of them is linked),
#     each crate's own license files from the build's cargo registry, its
#     Cargo.lock checksum, and for a crate without a file its Cargo.toml
#     license and authors with the standard text of that license.
set -euo pipefail
WORK="${1:?WORK_DIR}"; CACHE="${2:?SOURCE_CACHE}"; OUT="${3:?OUT_FILE}"
LIBSVM_COPYRIGHT="${LIBSVM_COPYRIGHT:-$(cd "$(dirname "$0")" && pwd)/notices-extra/libsvm-3.24-COPYRIGHT.txt}"
F="$WORK/build/out/bin/ffmpeg"
[ -x "$F" ] || { echo "no ffmpeg in $WORK" >&2; exit 1; }
conf="$("$F" -hide_banner -buildconf 2>&1)"

# configure flag → archive name prefix in the build's shim log
libs=(zlib)
add() { grep -q -- "$1" <<<"$conf" && libs+=("${@:2}") || true; }
add --enable-openssl openssl
add --enable-libxml2 libxml2
add --enable-libfreetype freetype
add --enable-fontconfig fontconfig
add --enable-libharfbuzz harfbuzz
add --enable-libass libass fribidi
add --enable-libsrt srt
add --enable-libdav1d dav1d
add --enable-libsnappy snappy
add --enable-libvmaf vmaf
add --enable-libklvanc libklvanc
add --enable-libzimg zimg
add --enable-libzvbi zvbi
add --enable-libaom libaom
add --enable-libopenh264 openh264
add --enable-libopenjpeg openjpeg
add --enable-librav1e rav1e
add --enable-libsvtav1 SVT-AV1
add --enable-libvpx libvpx
add --enable-libvvenc vvenc
add --enable-libwebp libwebp
add --enable-libx264 x264
add --enable-libx265 x265
add --enable-libmp3lame lame
add --enable-libopus opus
add --enable-libvorbis libvorbis libogg
add --enable-libtheora libtheora libogg

{
  echo "Libraries built into this download's FFmpeg (ffmpeg, ffprobe), with their"
  echo "license notices. Each entry: the library, its version, where its source"
  echo "came from and the SHA-256 of that archive; then its license text, unchanged."
  for lib in $(printf '%s\n' "${libs[@]}" | sort -u); do
    line="$(grep -E '^(SERVED|RECORDED) ' "$WORK/shim.log" | awk '{print $NF, $2}' | grep -E "/${lib}[-_.v0-9]*[^/]*$|/${lib}(_git)?/" | head -1 || true)"
    [ -n "$line" ] || { echo "gen-macos-library-notices: no source archive for $lib in $WORK/shim.log" >&2; exit 1; }
    url="${line% *}"; sha="${line##* }"
    arc="$(ls -1 "$CACHE/$sha"/* | head -1)"
    tmp="$(mktemp -d)"
    tar -xf "$arc" -C "$tmp" 2>/dev/null || { echo "cannot unpack $arc" >&2; exit 1; }
    top="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -1)"
    files="$("$(dirname "$0")/license-files.sh" "$top")"
    case "$lib" in libaom|SVT-AV1|libvpx|libwebp|rav1e|dav1d)
      grep -q -i -E '(^|/)patents' <<<"$files" || { echo "gen-macos-library-notices: $lib's PATENTS file is missing from its notice" >&2; exit 1; } ;;
    esac
    [ -n "$files" ] || { echo "gen-macos-library-notices: no license file in $(basename "$arc") for $lib" >&2; exit 1; }
    echo
    echo "================================================================================"
    echo "$lib — $(basename "$top") — source: $url — sha256 $sha"
    echo "================================================================================"
    while read -r f; do
      [ -n "$f" ] || continue
      if [ "${f#x86inc:}" != "$f" ]; then
        echo; echo "--- ${f#x86inc:} (its license header) ---"; echo; awk '/^;/ {print; next} {exit}' "$top/${f#x86inc:}"
      else
        echo; echo "--- $f ---"; echo; cat "$top/$f"
      fi
    done <<<"$files"
    if [ "$lib" = vmaf ] && [ -n "${LIBSVM_COPYRIGHT:-}" ]; then
      echo; echo "--- libsvm's COPYRIGHT (libvmaf's svm.cpp is libsvm) ---"; echo; cat "$LIBSVM_COPYRIGHT"
    fi
    rm -rf "$tmp"
  done

  if grep -q -- --enable-librav1e <<<"$conf"; then
    src="$(ls -d "$WORK"/build/source/rav1e/rav1e-*/ | head -1)"
    reg="$(ls -d "$WORK"/cargo-home/registry/src/*/ | head -1)"
    [ -f "$src/Cargo.lock" ] && [ -d "$reg" ] || { echo "gen-macos-library-notices: no rav1e source or cargo registry in $WORK" >&2; exit 1; }
    crates="$(cd "$src" && CARGO_HOME="$WORK/cargo-home" cargo tree --offline --locked -e normal --features capi \
                --target "$(lipo -archs "$F" | sed 's/^arm64$/aarch64/')-apple-darwin" --prefix none --format '{p}' 2>/dev/null \
              | grep -v -e '(proc-macro)' | sed 's/ (\*)$//' | awk '{print $1, $2}' | sort -u | grep -v '^rav1e ')" \
      || { echo "gen-macos-library-notices: cargo tree failed in $src" >&2; exit 1; }
    echo
    echo "================================================================================"
    echo "Rust crates compiled into rav1e (its library, as built): $(wc -l <<<"$crates" | tr -d ' ')"
    echo "================================================================================"
    printf '%s\n' "$crates" > "$tmp.crates"
    "$(dirname "$0")/crate-notices.sh" "$tmp.crates" "$reg" "$src/Cargo.lock" "$src" || exit 1
    rm -f "$tmp.crates"
    "$(dirname "$0")/rust-std-notice.sh" "${RUST_SRC:-$(rustc --print sysroot)/lib/rustlib/src/rust/library}" "$(rustc -V)" || exit 1
  fi
} > "$OUT"
echo "wrote $OUT ($(printf '%s\n' "${libs[@]}" | sort -u | tr '\n' ' '))"
