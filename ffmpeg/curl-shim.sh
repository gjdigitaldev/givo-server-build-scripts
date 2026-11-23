#!/bin/bash
# curl-shim.sh — stands in for `curl` while martin-riedl's FFmpeg build
# script runs (build-ffmpeg-macos.sh puts it first on PATH under the name
# `curl`). That script downloads every source with `curl -o NAME -L -f URL`
# and checks no checksum, so this shim does it instead:
#
#   - a URL listed in the manifest is served from the local cache, and only
#     when the cached file still has the manifest's SHA-256;
#   - SHIM_MODE=record: a URL not yet listed is downloaded once with the real
#     curl, stored in its own cache folder named by its SHA-256
#     (<cache>/<sha256>/<file>) and added to the manifest,
#     marked "tofu" (trust on first use: nothing upstream publishes a
#     checksum for most of these archives);
#   - a URL in the manifest but not yet in the cache (a first build) is fetched
#     — from SHIM_MIRROR first when set, https first for an http address — and
#     kept only when its SHA-256 is the manifest's;
#   - SHIM_MODE=verify (the default): a URL not in the manifest is refused,
#     so the build stops instead of picking up something new;
#   - prebuilt programs are always refused (CMake's release binaries): the
#     script then builds that tool from source.
#
# Manifest: one line per URL, tab separated:
#   url  sha256  bytes  first-fetch-date(UTC)  provenance
#
# Environment: SHIM_MANIFEST, SHIM_CACHE (folders/files on the build disk),
# SHIM_MODE (verify|record), SHIM_LOG (a log of every request), SHIM_MIRROR
# (optional: a copy of the cache, laid out <sha256>/<file>, tried first).
set -u

manifest="${SHIM_MANIFEST:?}"
cache="${SHIM_CACHE:?}"
mode="${SHIM_MODE:-verify}"
log="${SHIM_LOG:-/dev/null}"

out="" url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -L|-f|-s|-S|-fL|-fSL|-sS) shift ;;
    -*) echo "curl-shim: unsupported option $1" >&2; echo "REFUSED option $1" >> "$log"; exit 2 ;;
    *) url="$1"; shift ;;
  esac
done
[ -n "$out" ] && [ -n "$url" ] || { echo "curl-shim: need -o NAME and a URL" >&2; exit 2; }

case "$url" in
  https://github.com/Kitware/CMake/releases/download/*)
    echo "REFUSED prebuilt $url" >> "$log"
    echo "curl-shim: refusing a prebuilt program ($url); the script builds it from source" >&2
    exit 22 ;;
esac

sha="$(awk -F'\t' -v u="$url" '$1 == u { print $2; exit }' "$manifest" 2>/dev/null)"
if [ -n "$sha" ]; then
  f="$(ls -1 "$cache/$sha"/* 2>/dev/null | head -1)"
  if [ -z "$f" ]; then

    # empty SOURCE_CACHE): fetch it, from SHIM_MIRROR first when set (our own
    # copies, <mirror>/<sha256>/<file>), then upstream — over https when the
    # manifest's address is plain http — and keep it ONLY if its SHA-256 is the
    # manifest's. A different file is deleted and the build stops.
    mkdir -p "$cache"
    tmp="$(mktemp "$cache/.dl.XXXXXX")"
    got=""
    tries=()
    [ -n "${SHIM_MIRROR:-}" ] && tries+=("${SHIM_MIRROR%/}/$sha/$(basename "$out")")
    case "$url" in http://*) tries+=("https://${url#http://}") ;; esac
    tries+=("$url")
    for t in "${tries[@]}"; do
      if /usr/bin/curl -fL --retry 3 -o "$tmp" "$t" 2>>"$log"; then
        got="$(shasum -a 256 "$tmp" | awk '{print $1}')"
        [ "$got" = "$sha" ] && { from="$t"; break; }
        echo "MISMATCH $got (want $sha) from $t" >> "$log"
      fi
      got=""
    done
    if [ "$got" != "$sha" ]; then
      rm -f "$tmp"
      echo "curl-shim: could not get $url with SHA-256 $sha (see $log)" >&2
      echo "FETCH-FAILED $url" >> "$log"
      exit 22
    fi
    mkdir -p "$cache/$sha"
    mv "$tmp" "$cache/$sha/$(basename "$out")"
    f="$cache/$sha/$(basename "$out")"
    echo "FETCHED $sha $from" >> "$log"
  fi
  got="$(shasum -a 256 "$f" | awk '{print $1}')"
  [ "$got" = "$sha" ] || { echo "curl-shim: cached $url does not match its SHA-256" >&2; echo "BADSUM $url" >> "$log"; exit 22; }
  cp "$f" "$out"
  echo "SERVED $sha $url" >> "$log"
  exit 0
fi

if [ "$mode" != record ]; then
  echo "curl-shim: $url is not in the manifest — refused" >&2
  echo "REFUSED unknown $url" >> "$log"
  exit 22
fi

mkdir -p "$cache"
tmp="$(mktemp "$cache/.dl.XXXXXX")"
if ! /usr/bin/curl -fL --retry 3 -o "$tmp" "$url"; then
  rm -f "$tmp"
  echo "FAILED $url" >> "$log"
  exit 22
fi
sha="$(shasum -a 256 "$tmp" | awk '{print $1}')"
bytes="$(stat -f %z "$tmp")"
mkdir -p "$cache/$sha"
mv "$tmp" "$cache/$sha/$(basename "$out")"
printf '%s\t%s\t%s\t%s\t%s\n' "$url" "$sha" "$bytes" "$(date -u +%Y-%m-%dT%H:%MZ)" "tofu" >> "$manifest"
cp "$cache/$sha/$(basename "$out")" "$out"
echo "RECORDED $sha $bytes $url" >> "$log"
exit 0
