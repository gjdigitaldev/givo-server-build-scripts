#!/bin/bash
# conformance-macos.sh — runs every FFmpeg/ffprobe command shape GiVo Server
# issues (recording live HLS/TS over HTTP(S) and AES-128 HLS, catch-up parts,
# VOD saves with subtitles, finalize/trim/align, black and silence detection,
# scrub previews, embedded captions, caption audio, the casting relay, probes)
# against two or more ffmpeg builds and compares what comes out. Local test media only:
# made here with the reference build, served from 127.0.0.1 over HTTP and
# HTTPS (self-signed). No provider, no network beyond this Mac.
#
#   third_party/ffmpeg/conformance-macos.sh WORK_DIR REF_DIR CAND_DIR...
#     REF_DIR / CAND_DIR: folders holding ffmpeg + ffprobe (the reference is
#     today's bundled build; candidates are new builds)
#
# For each shape and build it records the exit code and, for outputs, the
# per-stream packet hashes (streamhash, MD5), packet counts, durations and the
# filters' detected times, then prints PASS (same as the reference), SAME-EXIT
# (both ran, outputs differ — listed) or FAIL (exit codes differ). Reports go to
# WORK_DIR/report.txt and WORK_DIR/<build>/<shape>.*
set -uo pipefail

WORK="${1:?usage: conformance-macos.sh WORK_DIR REF_DIR CAND_DIR...}"; shift
REF="${1:?}"; shift
[ $# -ge 1 ] || { echo "need at least one candidate" >&2; exit 2; }
CANDS=("$@")
mkdir -p "$WORK/media" "$WORK/www"
M="$WORK/media"; WWW="$WORK/www"
RF="$REF/ffmpeg"; RP="$REF/ffprobe"
HTTP_PORT=18080; HTTPS_PORT=18443
UA="GiVoConformance/1.0"

# ---------------------------------------------------------------- test media
gen() { "$RF" -hide_banner -loglevel error -y "$@"; }
if [ ! -f "$M/.done" ]; then
  # 60 s H.264/AAC TS: 20 s pattern, 3 s black + silence, 37 s pattern
  gen -f lavfi -i "testsrc2=size=1280x720:rate=25:duration=20" -f lavfi -i "color=black:size=1280x720:rate=25:duration=3" \
      -f lavfi -i "testsrc2=size=1280x720:rate=25:duration=37" \
      -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=20" -f lavfi -i "anullsrc=r=48000:cl=stereo:d=3" \
      -f lavfi -i "sine=frequency=660:sample_rate=48000:duration=37" \
      -filter_complex "[0:v][1:v][2:v]concat=n=3:v=1:a=0[v];[3:a]aformat=channel_layouts=stereo[a0];[5:a]aformat=channel_layouts=stereo[a2];[a0][4:a][a2]concat=n=3:v=0:a=1[a]" \
      -map "[v]" -map "[a]" -c:v libx264 -preset veryfast -g 50 -c:a aac -b:a 128k -f mpegts "$M/main.ts"
  # HLS (4 s segments), plain and AES-128
  mkdir -p "$WWW/hls" "$WWW/hlsaes"
  gen -i "$M/main.ts" -c copy -f hls -hls_time 4 -hls_list_size 0 -hls_segment_filename "$WWW/hls/s%03d.ts" "$WWW/hls/index.m3u8"
  head -c 16 /dev/urandom > "$WWW/hlsaes/k.key"
  printf 'http://127.0.0.1:%s/hlsaes/k.key\n%s\n' "$HTTP_PORT" "$WWW/hlsaes/k.key" > "$M/keyinfo"
  gen -i "$M/main.ts" -c copy -f hls -hls_time 4 -hls_list_size 0 -hls_key_info_file "$M/keyinfo" -hls_segment_filename "$WWW/hlsaes/s%03d.ts" "$WWW/hlsaes/index.m3u8"
  cp "$M/main.ts" "$WWW/live.ts"
  # VOD files: MP4 (needs h264_mp4toannexb into TS) and MKV with SubRip
  printf '1\n00:00:01,000 --> 00:00:04,000\nFirst caption line\n\n2\n00:00:10,000 --> 00:00:13,000\nSecond caption line\n' > "$M/subs.srt"
  gen -i "$M/main.ts" -c copy -t 30 "$WWW/movie.mp4"
  gen -i "$M/main.ts" -i "$M/subs.srt" -map 0 -map 1 -c copy -c:s srt -t 30 "$WWW/movie.mkv"
  # MPEG-2 (relay transcode) and HEVC (relay fMP4); AV1 (dav1d decoding)
  gen -i "$M/main.ts" -t 12 -c:v mpeg2video -b:v 4M -c:a mp2 -f mpegts "$WWW/mpeg2.ts"
  gen -i "$M/main.ts" -t 12 -c:v libx265 -preset ultrafast -x265-params log-level=error -c:a copy -f mpegts "$WWW/hevc.ts"
  gen -i "$M/main.ts" -t 6 -an -vf scale=640:-2 -c:v libaom-av1 -cpu-used 8 -row-mt 1 "$M/av1.mkv"
  touch "$M/.done"
fi
if [ ! -f "$M/.done2" ]; then
  gen -i "$WWW/hevc.ts" -c copy -tag:v hvc1 "$WWW/hevc.mp4"
  touch "$M/.done2"
fi

# ---------------------------------------------------------------- local servers
python3 -c 'import http.server' || { echo "python3 missing" >&2; exit 2; }
[ -f "$M/cert.pem" ] || /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -subj "/CN=127.0.0.1" -days 2 \
  -keyout "$M/key.pem" -out "$M/cert.pem" >/dev/null 2>&1
cat > "$M/serve.py" <<'PY'
import http.server, ssl, sys, functools, threading
root, hp, sp, cert, key = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4], sys.argv[5]
H = functools.partial(http.server.SimpleHTTPRequestHandler, directory=root)
class Q(http.server.ThreadingHTTPServer):
    daemon_threads = True
    def handle_error(self, *a): pass
http.server.SimpleHTTPRequestHandler.log_message = lambda *a: None
h = Q(("127.0.0.1", hp), H)
s = Q(("127.0.0.1", sp), H)
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); ctx.load_cert_chain(cert, key)
s.socket = ctx.wrap_socket(s.socket, server_side=True)
threading.Thread(target=h.serve_forever, daemon=True).start()
s.serve_forever()
PY
python3 "$M/serve.py" "$WWW" "$HTTP_PORT" "$HTTPS_PORT" "$M/cert.pem" "$M/key.pem" &
SERVER=$!
trap 'kill $SERVER 2>/dev/null' EXIT
sleep 1
HTTP="http://127.0.0.1:$HTTP_PORT"; HTTPS="https://127.0.0.1:$HTTPS_PORT"

# ---------------------------------------------------------------- the shapes
# Each shape is a function run with $F/$P = the build's ffmpeg/ffprobe and
# $O = its output folder; it writes its outputs into $O/<shape>.* .
REC_IN=(-hide_banner -loglevel warning -user_agent "$UA" -rw_timeout 15000000 -reconnect 1 -reconnect_streamed 1
        -reconnect_delay_max 5 -probesize 10000000 -analyzeduration 10000000 -fflags +discardcorrupt+genpts
        -correct_ts_overflow 0 -headers $'X-Conformance: 1\r\n')
TS_OUT=(-f mpegts -mpegts_flags +resend_headers -pat_period 0.5)
HLS_MAPS=(-map 0:p:0 -map -0:p:0 -map '0:p:0:v?' -map '0:p:0:a?' -sn)
TS_MAPS=(-map 0 -map -0 -map '0:v?' -map '0:a?' -map '0:s?')

s_rec_hls_https()   { "$F" "${REC_IN[@]}" -i "$HTTPS/hls/index.m3u8" "${HLS_MAPS[@]}" -dn -c copy -avoid_negative_ts make_zero -muxpreload 0 -muxdelay 0 "${TS_OUT[@]}" -y "$O/rec_hls_https.ts"; }
s_rec_hls_aes()     { "$F" "${REC_IN[@]}" -i "$HTTP/hlsaes/index.m3u8" "${HLS_MAPS[@]}" -dn -c copy -avoid_negative_ts make_zero -muxpreload 0 -muxdelay 0 "${TS_OUT[@]}" -y "$O/rec_hls_aes.ts"; }
s_rec_ts_http()     { "$F" "${REC_IN[@]}" -i "$HTTP/live.ts" "${TS_MAPS[@]}" -dn -c copy -avoid_negative_ts make_zero -muxpreload 0 -muxdelay 0 "${TS_OUT[@]}" -y "$O/rec_ts_http.ts"; }
s_rec_hls_map0()    { "$F" "${REC_IN[@]}" -i "$HTTPS/hls/index.m3u8" -map 0 -map -0 -map '0:v?' -map '0:a?' -sn -dn -c copy -avoid_negative_ts make_zero -muxpreload 0 -muxdelay 0 "${TS_OUT[@]}" -y "$O/rec_hls_map0.ts"; }   # R54a's -map 0 fallback on HLS
s_vod_hevc_mp4()    { "$F" "${REC_IN[@]}" -i "$HTTPS/hevc.mp4" -map 0 -dn -c copy -avoid_negative_ts make_zero -muxpreload 0 -muxdelay 0 -bsf:v:0 hevc_mp4toannexb "${TS_OUT[@]}" -y "$O/vod_hevc_mp4.ts"; }
s_concat_inpoint()  { printf "file '%s'\nfile '%s'\ninpoint 3.000\n" "$O/rec_ts_http.ts" "$O/rec_part_offset.ts" > "$O/concat_inpoint.list"
                      "$F" -hide_banner -loglevel error -f concat -safe 0 -i "$O/concat_inpoint.list" -map 0 -c copy -avoid_negative_ts make_zero -y "$O/concat_inpoint.ts"; }
s_cc_seek_point()   { (cd "$M" && "$F" -hide_banner -loglevel error -y -data_field first -f lavfi -i "movie=main.ts:seek_point=12.000[out0+subcc]" -t 20.000 -map 0:s:0 -c:s webvtt -f webvtt "$O/cc_seek.vtt"); }
s_relay_mpeg2_x264(){ if ! "$F" -hide_banner -encoders 2>/dev/null | grep -q -E ' libx264 '; then echo "libx264 not listed: the server does not start this cast" > "$O/relay_mpeg2_x264.txt"; return 0; fi
                      mkdir -p "$O/relay_mpeg2_x264"; "$F" -hide_banner -loglevel warning -i "$HTTP/mpeg2.ts" -map 0:v:0 -map '0:a:0?' -sn -dn -c:v libx264 -preset veryfast -crf 21 -pix_fmt yuv420p -c:a aac -b:a 160k -ac 2 -f hls -hls_time 2 -hls_list_size 6 -hls_flags delete_segments+independent_segments -start_number 0 -hls_segment_type mpegts -hls_segment_filename "$O/relay_mpeg2_x264/seg%d.ts" "$O/relay_mpeg2_x264/live.m3u8"; }
s_relay_retries()   { mkdir -p "$O/relay_retries"; "$F" -hide_banner -loglevel warning -user_agent "$UA" -headers $'X-Conformance: 1\r\n' -reconnect_max_retries 1 -rw_timeout 15000000 -reconnect 1 -reconnect_streamed 1 -reconnect_delay_max 5 -i "$HTTPS/live.ts" -map 0:v:0 -map '0:a:0?' -sn -dn -c:v copy -c:a aac -b:a 160k -ac 2 -t 8 -f hls -hls_time 2 -hls_list_size 6 -hls_flags delete_segments+independent_segments -start_number 0 -hls_segment_type mpegts -hls_segment_filename "$O/relay_retries/seg%d.ts" "$O/relay_retries/live.m3u8"; }
s_probe_vod()       { "$P" -v warning -print_format json -show_streams -show_format -probesize 5000000 -analyzeduration 5000000 -user_agent "$UA" "$HTTPS/movie.mkv" > "$O/probe_vod.json"; }
s_rec_part_offset() { "$F" "${REC_IN[@]}" -copyts -start_at_zero -i "$HTTPS/live.ts" -ss 2.000000 "${TS_MAPS[@]}" -dn -c copy -avoid_negative_ts disabled -muxpreload 0 -muxdelay 0 -output_ts_offset 30.000000 -t 20.000000 "${TS_OUT[@]}" -y "$O/rec_part_offset.ts"; }
s_vod_mp4()         { "$F" "${REC_IN[@]}" -i "$HTTPS/movie.mp4" -map 0 -dn -c copy -avoid_negative_ts make_zero -muxpreload 0 -muxdelay 0 -bsf:v:0 h264_mp4toannexb "${TS_OUT[@]}" -y "$O/vod_mp4.ts"; }
s_vod_mkv_subs()    { "$F" "${REC_IN[@]}" -copyts -start_at_zero -i "$HTTPS/movie.mkv" -map 0 -dn -c copy -avoid_negative_ts disabled -muxpreload 0 -muxdelay 0 -map -0:s -bsf:v:0 h264_mp4toannexb "${TS_OUT[@]}" -y "$O/vod_mkv_subs.ts" \
                        -map 0:s:0 -c:s webvtt -avoid_negative_ts disabled -f webvtt -y "$O/vod_mkv_subs.vtt"; }
s_concat()          { printf "file '%s'\nfile '%s'\n" "$O/rec_ts_http.ts" "$O/rec_part_offset.ts" > "$O/concat.list"
                      "$F" -hide_banner -loglevel error -f concat -safe 0 -i "$O/concat.list" -t 70.000 -map 0 -c copy -avoid_negative_ts make_zero -y "$O/concat.ts"; }
s_trim()            { "$F" -hide_banner -loglevel error -i "$O/rec_ts_http.ts" -t 30.000 -map 0 -c copy -avoid_negative_ts make_zero -y "$O/trim.ts"; }
s_align()           { "$F" -hide_banner -loglevel error -copyts -i "$O/rec_ts_http.ts" -map 0:0 -map 0:1 -c copy -muxdelay 0 -muxpreload 0 -avoid_negative_ts disabled -f mpegts -y "$O/align.ts"; }
s_detect()          { (cd "$M" && "$F" -hide_banner -nostats -i main.ts -vf "blackdetect=d=1:pix_th=0.10" -af "silencedetect=noise=-50dB:d=1" -f null - 2>&1) | grep -E 'black_start|silence_(start|end)' | sed 's/.*\] //' > "$O/detect.txt"; [ -s "$O/detect.txt" ]; }
s_detect_window()   { (cd "$M" && "$F" -hide_banner -nostats -ss 15 -t 15 -i main.ts -vf "blackdetect=d=0.5:pic_th=0.98:pix_th=0.10" -af "silencedetect=noise=-50dB:d=0.5" -f null - 2>&1) | grep -E 'black_start|silence_(start|end)' | sed 's/.*\] //' > "$O/detect_window.txt"; [ -s "$O/detect_window.txt" ]; }
s_subfile()         { local sz; sz=$(stat -f %z "$M/main.ts"); (cd "$M" && "$F" -hide_banner -nostats -i "subfile,,start,0,end,$((sz/2)),,:main.ts" -vf "blackdetect=d=0.5:pix_th=0.10" -f null - 2>&1) | grep -E 'black_start' | sed 's/.*\] //' > "$O/subfile.txt"; [ -s "$O/subfile.txt" ]; }
s_actin()           { (cd "$M" && "$F" -hide_banner -nostats -loglevel error -ss 5 -t 10 -i main.ts -filter_complex "[0:v]split=2[a][b];[a]crop=128:72:0:0[tl];[b]crop=128:72:1152:0[tr];[tl][tr]hstack,fps=2,format=gray[o]" -map "[o]" -f rawvideo -) > "$O/actin.raw"; }
s_thumb_grid()      { mkdir -p "$O/grid"; (cd "$M" && "$F" -hide_banner -nostats -loglevel error -hwaccel auto -ss 0 -t 60 -i main.ts -vf "fps=1/10,scale=320:-2" -q:v 5 -start_number 1 -y -f image2 "$O/grid/t.thumb%04d.jpg"); ls "$O/grid" | wc -l > "$O/thumb_grid.txt"; }
s_thumb_at()        { (cd "$M" && "$F" -hide_banner -nostats -loglevel error -ss 25.000 -i main.ts -frames:v 1 -vf "scale=320:-2" -q:v 5 -y "$O/thumb_at.jpg"); }
s_thumb_byte()      { (cd "$M" && "$F" -hide_banner -nostats -loglevel error -skip_initial_bytes 4000000 -i main.ts -frames:v 1 -vf "scale=320:-2" -q:v 5 -y "$O/thumb_byte.jpg"); }
s_cc_lavfi()        { (cd "$M" && "$F" -hide_banner -loglevel error -y -data_field first -f lavfi -i "movie=main.ts[out0+subcc]" -map 0:s:0 -c:s webvtt -f webvtt "$O/cc.vtt"); }
s_whisper_wav()     { "$F" -hide_banner -loglevel error -y -ss 10 -t 20 -i "$M/main.ts" -vn -ac 1 -ar 16000 -c:a pcm_s16le -f wav "$O/whisper.wav"; }
s_relay_h264()      { mkdir -p "$O/relay_h264"; "$F" -hide_banner -loglevel warning -user_agent "$UA" -rw_timeout 15000000 -reconnect 1 -reconnect_streamed 1 -reconnect_delay_max 5 -probesize 10000000 -analyzeduration 10000000 -fflags +discardcorrupt+genpts -i "$HTTPS/live.ts" -map 0:v:0 -map '0:a:0?' -sn -dn -c:v copy -c:a aac -b:a 160k -ac 2 -t 12 -f hls -hls_time 2 -hls_list_size 6 -hls_flags delete_segments+independent_segments -start_number 0 -hls_segment_type mpegts -hls_segment_filename "$O/relay_h264/seg%d.ts" "$O/relay_h264/live.m3u8"; }
s_relay_mpeg2_vt()  { mkdir -p "$O/relay_mpeg2_vt"; "$F" -hide_banner -loglevel warning -user_agent "$UA" -rw_timeout 15000000 -i "$HTTP/mpeg2.ts" -map 0:v:0 -map '0:a:0?' -sn -dn -c:v h264_videotoolbox -b:v 4000k -realtime 1 -pix_fmt yuv420p -c:a aac -b:a 160k -ac 2 -f hls -hls_time 2 -hls_list_size 6 -hls_flags delete_segments+independent_segments -start_number 0 -hls_segment_type mpegts -hls_segment_filename "$O/relay_mpeg2_vt/seg%d.ts" "$O/relay_mpeg2_vt/live.m3u8"; }
s_relay_hevc_fmp4() { mkdir -p "$O/relay_hevc_fmp4"; "$F" -hide_banner -loglevel warning -user_agent "$UA" -rw_timeout 15000000 -i "$HTTP/hevc.ts" -map 0:v:0 -map '0:a:0?' -sn -dn -c:v copy -c:a aac -b:a 160k -ac 2 -f hls -hls_time 2 -hls_list_size 6 -hls_flags delete_segments+independent_segments -start_number 0 -hls_segment_type fmp4 -hls_fmp4_init_filename init.mp4 -hls_segment_filename "$O/relay_hevc_fmp4/seg%d.m4s" "$O/relay_hevc_fmp4/live.m3u8"; }
s_av1_decode()      { (cd "$M" && "$F" -hide_banner -nostats -loglevel error -i av1.mkv -vf "fps=1,scale=160:-2" -q:v 5 -y -f image2 "$O/av1_%02d.jpg") && ls "$O"/av1_*.jpg | wc -l > "$O/av1_decode.txt"; }
s_probe_hls()       { "$P" -hide_banner -loglevel error -user_agent "$UA" -rw_timeout 15000000 -print_format json -show_streams -show_format -i "$HTTPS/hls/index.m3u8" > "$O/probe_hls.json"; }
s_probe_frames()    { "$P" -hide_banner -loglevel error -select_streams v:0 -read_intervals "%+#300" -show_frames -show_entries frame=side_data_list -print_format json -i "$M/main.ts" > "$O/probe_frames.json"; }
s_probe_csv()       { "$P" -v error -show_entries format=start_time,duration -of csv=p=0 "$M/main.ts" > "$O/probe_csv.txt"; }
s_probe_geom()      { "$P" -v error -select_streams v:0 -show_entries stream=width,height -of json "$M/main.ts" > "$O/probe_geom.json"; }
s_help_http()       { "$F" -hide_banner -h protocol=http 2>&1 | grep -o reconnect_max_retries | head -1 > "$O/help_http.txt"; [ -s "$O/help_http.txt" ]; }
s_encoders_vt()     { "$F" -hide_banner -encoders 2>/dev/null | grep -o h264_videotoolbox | head -1 > "$O/encoders_vt.txt"; [ -s "$O/encoders_vt.txt" ]; }

SHAPES=(rec_hls_https rec_hls_aes rec_hls_map0 rec_ts_http rec_part_offset vod_mp4 vod_hevc_mp4 vod_mkv_subs concat
        concat_inpoint trim align detect detect_window subfile actin thumb_grid thumb_at thumb_byte cc_lavfi cc_seek_point
        whisper_wav relay_h264 relay_mpeg2_vt relay_mpeg2_x264 relay_hevc_fmp4 relay_retries av1_decode probe_hls
        probe_frames probe_csv probe_geom probe_vod help_http encoders_vt)

# What to compare for a shape's outputs (measured with the REFERENCE ffprobe/ffmpeg).
summary() { # $1 output folder, $2 shape → one line per output file
  local o="$1" sh="$2" f
  for f in "$o/$sh".ts "$o/$sh".vtt "$o/$sh".wav "$o/$sh".raw "$o/$sh".jpg "$o/$sh".txt "$o/$sh".json \
           "$o/$sh/live.m3u8"; do
    [ -f "$f" ] || continue
    case "$f" in
      *.ts) echo "$(basename "$f"): $("$RF" -hide_banner -loglevel error -i "$f" -map 0 -c copy -f streamhash -hash md5 - 2>/dev/null | tr '\n' ' ') pkts=$("$RP" -v error -count_packets -show_entries stream=codec_name,nb_read_packets -of csv=p=0 "$f" | tr '\n' ' ') dur=$("$RP" -v error -show_entries format=duration -of csv=p=0 "$f")" ;;
      *.m3u8) d="$(dirname "$f")"; echo "$(basename "$d"): segments=$(ls "$d" | grep -c -E 'seg[0-9]+\.(ts|m4s)$') codecs=$("$RP" -v error -show_entries stream=codec_name -of csv=p=0 "$d/$(ls "$d" | grep -E 'seg0\.(ts|m4s)$' | head -1)" 2>/dev/null | tr '\n' ' ')" ;;
      *.vtt|*.txt) echo "$(basename "$f"): $(shasum -a 256 < "$f" | cut -c1-16) $(tr '\n' '|' < "$f" | cut -c1-200)" ;;
      *.json) echo "$(basename "$f"): $(python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
keys = ("codec_type", "codec_name", "profile", "width", "height", "pix_fmt", "color_transfer", "sample_rate", "channels", "channel_layout", "duration")
st = [{k: x.get(k) for k in keys if x.get(k) is not None} | {"lang": (x.get("tags") or {}).get("language")} for x in d.get("streams", [])]
fr = d.get("frames", [])
sd = sorted({s.get("side_data_type") for f in fr for s in f.get("side_data_list", []) or []} - {None})
fo = {k: d.get("format", {}).get(k) for k in ("format_name", "duration", "nb_streams")} if "format" in d else {}
print(json.dumps({"streams": st, "frames": len(fr), "side_data": sd, "format": fo}, sort_keys=True))' "$f")" ;;
      *) echo "$(basename "$f"): $(stat -f %z "$f") bytes $(shasum -a 256 < "$f" | cut -c1-16)" ;;
    esac
  done
  case "$sh" in
    thumb_grid) echo "jpgs=$(cat "$o/thumb_grid.txt" | tr -d ' ') all=$(cat "$o"/grid/*.jpg 2>/dev/null | shasum -a 256 | cut -c1-16)" ;;
    av1_decode) echo "jpgs=$(cat "$o/av1_decode.txt" 2>/dev/null | tr -d ' ') all=$(cat "$o"/av1_*.jpg 2>/dev/null | shasum -a 256 | cut -c1-16)" ;;
    cc_lavfi) [ -f "$o/cc.vtt" ] && echo "cc.vtt: $(stat -f %z "$o/cc.vtt") bytes $(shasum -a 256 < "$o/cc.vtt" | cut -c1-16)" || echo "cc.vtt: none" ;;
    cc_seek_point) [ -f "$o/cc_seek.vtt" ] && echo "cc_seek.vtt: $(stat -f %z "$o/cc_seek.vtt") bytes $(shasum -a 256 < "$o/cc_seek.vtt" | cut -c1-16)" || echo "cc_seek.vtt: none" ;;
    whisper_wav) [ -f "$o/whisper.wav" ] && echo "whisper.wav: $(stat -f %z "$o/whisper.wav") bytes $(shasum -a 256 < "$o/whisper.wav" | cut -c1-16)" || echo "whisper.wav: none" ;;
    relay_*) echo "segment bytes: $(cat "$o/$sh"/seg* "$o/$sh"/init.mp4 2>/dev/null | shasum -a 256 | cut -c1-16)" ;;
  esac
}

run_build() { # $1 label, $2 dir
  local label="$1" dir="$2" sh rc
  F="$dir/ffmpeg"; P="$dir/ffprobe"; O="$WORK/$label"
  rm -rf "$O"; mkdir -p "$O"
  for sh in "${SHAPES[@]}"; do
    "s_$sh" > "$O/$sh.log" 2>&1; rc=$?
    echo "$rc" > "$O/$sh.rc"
    summary "$O" "$sh" > "$O/$sh.sum" 2>/dev/null
  done
}

run_build ref "$REF"
labels=(); dirs=()
for c in "${CANDS[@]}"; do l="$(basename "$c")"; labels+=("$l"); dirs+=("$c"); run_build "$l" "$c"; done

{
  echo "conformance $(date -u +%Y-%m-%dT%H:%MZ) — reference: $REF ($("$RF" -hide_banner -version | head -1))"
  for i in "${!labels[@]}"; do echo "candidate ${labels[$i]}: ${dirs[$i]} ($("${dirs[$i]}/ffmpeg" -hide_banner -version 2>/dev/null | head -1))"; done
  for sh in "${SHAPES[@]}"; do
    line="$(printf '%-17s ref=%s' "$sh" "$(cat "$WORK/ref/$sh.rc")")"
    for l in "${labels[@]}"; do
      rr="$(cat "$WORK/ref/$sh.rc")"; cr="$(cat "$WORK/$l/$sh.rc")"
      if [ "$rr" != "$cr" ]; then v=FAIL
      elif cmp -s "$WORK/ref/$sh.sum" "$WORK/$l/$sh.sum"; then v=PASS
      else v=SAME-EXIT; fi
      line="$line  $l=$cr:$v"
    done
    echo "$line"
  done
  echo
  echo "Differences (reference first, then each candidate):"
  for sh in "${SHAPES[@]}"; do
    for l in "${labels[@]}"; do
      if ! cmp -s "$WORK/ref/$sh.sum" "$WORK/$l/$sh.sum" || [ "$(cat "$WORK/ref/$sh.rc")" != "$(cat "$WORK/$l/$sh.rc")" ]; then
        echo "--- $sh ($l)"; sed 's/^/  ref: /' "$WORK/ref/$sh.sum"; sed "s/^/  $l: /" "$WORK/$l/$sh.sum"
        [ "$(cat "$WORK/$l/$sh.rc")" = 0 ] || sed "s/^/  $l log: /" "$WORK/$l/$sh.log" | tail -3
      fi
    done
  done
} > "$WORK/report.txt"
cat "$WORK/report.txt"
