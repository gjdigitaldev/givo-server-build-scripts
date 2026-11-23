#!/bin/bash
# check-windows-library-notices.sh FFMPEG_DIR NOTICE_FILE
#
# checks a Windows FFmpeg
# build's library notice against the build itself, not against the list that
# wrote it: each library is recognised in ffmpeg.exe/ffprobe.exe by its own
# text (version banner, API name, URI, error text, from `strings`; nothing is
# run), and every library recognised must have its entry in the notice. Exits 1
# when one has none. package-windows.sh runs it on the staged pair, and
# gen-licenses.sh on the macOS universal pair (ffmpeg, ffprobe: each slice is
# read on its own; the macOS notice's names for aom, SVT-AV1, opus and lame are
# mapped below).
#
# Each signature row: the notice entry name, then an extended regex matched on
# the strings with the configure line taken out (its --disable-… words name
# libraries that are not there), or "flag:--enable-…" for evidence from the
# configure line itself.
set -uo pipefail
D="${1:?folder with ffmpeg.exe and ffprobe.exe}"; NOTICE="${2:?notice file}"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
for n in ffmpeg ffprobe; do
  f="$D/$n.exe"; [ -f "$f" ] || f="$D/$n"; [ -f "$f" ] || { echo "no $D/$n(.exe)" >&2; exit 2; }
  archs="$(lipo -archs "$f" 2>/dev/null || true)"
  if [ "$(echo "$archs" | wc -w)" -gt 1 ]; then for a in $archs; do lipo "$f" -thin "$a" -output "$tmp/slice" && strings -n 4 "$tmp/slice"; done
  else strings -n 4 "$f"; fi
done > "$tmp/all"
LC_ALL=C grep -a -o -E -- '--enable-[a-z0-9-]+' "$tmp/all" | sort -u > "$tmp/flags"
LC_ALL=C grep -a -v -E -- '--(enable|disable)-[a-z0-9]' "$tmp/all" > "$tmp/s"
LC_ALL=C grep -a -E '^[A-Za-z0-9_.+-]+ — ' "$NOTICE" | sed 's/ — .*//' | sort -u > "$tmp/have"
LC_ALL=C grep -a -q '^The Rust standard library' "$NOTICE" && echo "rust-std" >> "$tmp/have"
sed -e 's/^libaom$/aom/' -e 's/^SVT-AV1$/svtav1/' -e 's/^opus$/libopus/' -e 's/^lame$/libmp3lame/' "$tmp/have" > "$tmp/alias" # the macOS notice's names
cat "$tmp/alias" >> "$tmp/have"
fail=0; found=0
while IFS=$'\t' read -r name re; do
  case "$name" in ''|\#*) continue ;; esac
  case "$re" in
    flag:*) grep -q -x -F -- "${re#flag:}" "$tmp/flags" || continue ;;
    *) LC_ALL=C grep -a -q -E -- "$re" "$tmp/s" || continue ;;
  esac
  found=$((found + 1))
  if grep -q -x -F "$name" "$tmp/have"; then printf '  %-18s in the binary, in the notice\n' "$name"
  else printf '  %-18s IN THE BINARY, NOT IN THE NOTICE\n' "$name"; fail=1; fi
done <<'SIG'
x264	x264 - core [0-9]+
x265	x265 \[info\]|HEVC encoder version
libvpx	WebM Project VP[89] (En|De)coder
aom	AOMedia Project AV1 (En|De)coder
dav1d	dav1d_(send_data|get_picture)|^dav1d 1\.
svtav1	SVT-AV1|svt_av1_enc_init
rav1e	rav1e_(context_new|send_frame)|rav1e 0\.
rust-std	/rustc/[0-9a-f]{40}/library
openssl	OpenSSL 3\.[0-9]+\.[0-9]+
srt	srt_(startup|connect)|SRT version
zlib	(deflate|inflate) [0-9.]+ Copyright .*(Gailly|Adler)
xz	liblzma|lzma_(stream_decoder|code)
libxml2	xmlReadMemory|libxml2
freetype	FT_(Init_FreeType|New_Face)
fontconfig	FONTCONFIG_FILE|FcConfigParseAndLoad
harfbuzz	hb_buffer_create|HarfBuzz
fribidi	fribidi_
libass	libass|ass_render_frame
brotli	reklamaothers
lcms2	Little CMS|cmsCreateContext
libpng	libpng version
mbedtls	mbedtls_ctr_drbg_seed|mbedtls_
lv2	lv2plug\.in/ns
lilv	lilv_world_new|lilv
serd	serd_reader|serd_
sord	sord_
zix	zix_
sratom	sratom_
libdvdcss	libdvdcss
libdvdread	libdvdread|DVDOpen
libdvdnav	dvdnav_
glslang	glslang
spirv-tools	SPIRV-Tools|spvtools
spirv-cross	spirv_cross|SPIRV-Cross
highway	hwy::|HWY_
mingw	Mingw-w64 runtime failure|_pei386_runtime_relocator
libjxl	JxlDecoder|libjxl
openh264	OpenH264|WelsCreate
openjpeg	OpenJPEG|opj_decode
libwebp	WebPEncode|WebPDecode
zimg	zimg_
vmaf	vmaf_init|libvmaf
snappy	snappy
soxr	soxr_(create|process)|libsoxr
twolame	twolame_
libopus	opus_(encode|decode)|libopus
libvorbis	Xiph.Org libVorbis
libogg	ogg_stream_
libtheora	Xiph.Org libtheora|th_decode
libmp3lame	LAME [0-9]\.|lame_init
opencore-amr	Decoder_Interface_init|Encoder_Interface_init
xvid	xvid_(global|decore|encore)
kvazaar	kvazaar|kvz_
davs2	flag:--enable-libdavs2
xavs2	flag:--enable-libxavs2
uavs3d	flag:--enable-libuavs3d
gme	gme_(open|play)|Game_Music_Emu
openmpt	flag:--enable-libopenmpt
chromaprint	chromaprint
fftw3	fftw_|FFTW
rubberband	RubberBand|Rubber Band
libsamplerate	Band limited sinc interpolation|Secret Rabbit Code
libzmq	zmq_(ctx_new|socket)
libssh	libssh
librist	rist_(receiver|sender)_create|librist
libbluray	libbluray|bd_open
libudfread	udfread
libaribb24	arib_instance|aribb24
libaribcaption	aribcc_
openal	OpenAL Soft
vidstab	vidstab|vid\.stab
libplacebo	flag:--enable-libplacebo
shaderc	shaderc_
vulkan-loader	vulkan-1\.dll
gmp	__gmp|GNU MP
libiconv	libiconv|libcharset
libunibreak	unibreak|set_linebreaks
frei0r	flag:--enable-frei0r
avisynth	flag:--enable-avisynth
amf	flag:--enable-amf
ffnvcodec	flag:--enable-ffnvcodec
opencl	flag:--enable-opencl
opencl-icd-loader	OCL_ICD_(FILENAMES|VENDORS|ENABLE_TRACE)
onevpl	flag:--enable-libvpl
libva	flag:--enable-vaapi
lcevcdec	flag:--enable-liblcevc-dec
openapv	flag:--enable-liboapv
vvenc	flag:--enable-libvvenc
sdl	flag:--enable-sdl2-NEVER
SIG
echo "notice check: $found libraries recognised in the binaries, $([ $fail = 0 ] && echo 'every one in the notice: PASS' || echo 'some MISSING from the notice: FAIL')"
exit $fail
