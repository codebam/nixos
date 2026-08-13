#!/usr/bin/env bash
# Stream the whole display (TTY console *and* Wayland session) to YouTube via HLS.
#
# Capture happens at the KMS level (ffmpeg -f kmsgrab), so it follows whatever is
# currently scanned out to the monitor -- the VT console framebuffer as well as the
# compositor's. Requires CAP_SYS_ADMIN, hence the run0 re-exec.
#
# Stream key comes from `pass show youtube-hls` by default, read as the invoking
# user (the GPG agent lives in that session, not root's).
#
# Usage: ./stream-display.sh [--codec av1|hevc|h264] [--pass-entry NAME | --key-file PATH]
#                            [--fps N] [--bitrate 6M] [--size WxH]
#
# Env overrides: CODEC PASS_ENTRY KEY_FILE FPS BITRATE SIZE KMS_DEVICE VAAPI_DEVICE

set -euo pipefail

CODEC="${CODEC:-av1}"
PASS_ENTRY="${PASS_ENTRY:-youtube-hls}"
KEY_FILE="${KEY_FILE:-}"
FPS="${FPS:-30}"
BITRATE="${BITRATE:-6M}"
SIZE="${SIZE:-}"          # empty = native resolution
KMS_DEVICE="${KMS_DEVICE:-}"
VAAPI_DEVICE="${VAAPI_DEVICE:-/dev/dri/renderD128}"
INGEST="https://a.upload.youtube.com/http_upload_hls"

while [ $# -gt 0 ]; do
	case "$1" in
	--codec) CODEC="$2"; shift 2 ;;
	--key-file) KEY_FILE="$2"; PASS_ENTRY=""; shift 2 ;;
	--pass-entry) PASS_ENTRY="$2"; KEY_FILE=""; shift 2 ;;
	--fps) FPS="$2"; shift 2 ;;
	--bitrate) BITRATE="$2"; shift 2 ;;
	--size) SIZE="$2"; shift 2 ;;
	--kms-device) KMS_DEVICE="$2"; shift 2 ;;
	-h | --help) sed -n '2,15p' "$0"; exit 0 ;;
	*) echo "unknown arg: $1" >&2; exit 2 ;;
	esac
done

# FEED_FORMAT is the container carried over the internal FIFO. It must survive the
# capture process restarting mid-stream. MPEG-TS does that by design; for AV1 it is
# not an option (ffmpeg muxes AV1 into TS as an undeclared private stream and cannot
# demux its own output), so AV1 rides as raw OBU instead -- a restart just injects a
# fresh sequence header, which the demuxer picks up.
case "$CODEC" in
av1) ENCODER=av1_vaapi; SEGMENT_TYPE=fmp4; FEED_FORMAT=obu ;;
hevc) ENCODER=hevc_vaapi; SEGMENT_TYPE=mpegts; FEED_FORMAT=mpegts ;;
h264) ENCODER=h264_vaapi; SEGMENT_TYPE=mpegts; FEED_FORMAT=mpegts ;;
*) echo "unknown codec: $CODEC (av1|hevc|h264)" >&2; exit 2 ;;
esac

# --- privilege escalation ------------------------------------------------------
# kmsgrab needs CAP_SYS_ADMIN. Re-exec under run0. The key itself is deliberately
# NOT passed through argv or the environment (both are world-readable via /proc and
# systemd unit properties) -- it goes into a 0600 file whose path is handed over
# instead, and the privileged half unlinks it immediately after reading.
if [ "${STREAM_DISPLAY_PRIVILEGED:-}" != 1 ]; then
	if [ -n "$PASS_ENTRY" ]; then
		KEY_FILE="$(mktemp -t stream-key.XXXXXX)"
		chmod 600 "$KEY_FILE"
		trap 'rm -f "$KEY_FILE"' EXIT INT TERM
		pass show "$PASS_ENTRY" >"$KEY_FILE"
	fi
	[ -s "$KEY_FILE" ] || { echo "no stream key (${PASS_ENTRY:-$KEY_FILE})" >&2; exit 1; }
	exec run0 \
		--setenv=STREAM_DISPLAY_PRIVILEGED=1 \
		--setenv=KEY_FILE="$KEY_FILE" \
		--setenv=KEY_FILE_EPHEMERAL="${PASS_ENTRY:+1}" \
		--setenv=CODEC="$CODEC" \
		--setenv=FPS="$FPS" \
		--setenv=BITRATE="$BITRATE" \
		--setenv=SIZE="$SIZE" \
		--setenv=KMS_DEVICE="$KMS_DEVICE" \
		--setenv=VAAPI_DEVICE="$VAAPI_DEVICE" \
		-- "$(realpath "$0")"
fi

# --- from here on: running as root ---------------------------------------------
STREAM_KEY="$(tr -d '[:space:]' <"$KEY_FILE")"
[ "${KEY_FILE_EPHEMERAL:-}" = 1 ] && rm -f "$KEY_FILE" || true
[ -n "$STREAM_KEY" ] || { echo "stream key is empty" >&2; exit 1; }

# Pick the DRM card that actually has a connected, enabled connector.
if [ -z "$KMS_DEVICE" ]; then
	for card in /sys/class/drm/card[0-9]*-*; do
		[ -e "$card/status" ] || continue
		[ "$(cat "$card/status")" = connected ] || continue
		[ "$(cat "$card/enabled" 2>/dev/null)" = enabled ] || continue
		KMS_DEVICE="/dev/dri/$(basename "${card%%-*}")"
		break
	done
fi
[ -n "$KMS_DEVICE" ] || { echo "no active DRM card found" >&2; exit 1; }

FFMPEG=(nix run --extra-experimental-features 'nix-command flakes' nixpkgs#ffmpeg-full --)

VF="hwmap=derive_device=vaapi"
if [ -n "$SIZE" ]; then
	VF="$VF,scale_vaapi=${SIZE/x/:}:format=nv12"
else
	VF="$VF,scale_vaapi=format=nv12"
fi

CAPTURE_IN=(
	-init_hw_device "vaapi=vd:$VAAPI_DEVICE" -filter_hw_device vd
	-device "$KMS_DEVICE" -f kmsgrab -framerate "$FPS" -i -
)
CAPTURE_OUT=(-vf "$VF" -c:v "$ENCODER" -b:v "$BITRATE" -g "$((FPS * 2))")

HLS=(
	-f hls -hls_time 2 -hls_list_size 6
	-hls_flags independent_segments+append_list+omit_endlist
	-hls_segment_type "$SEGMENT_TYPE"
	-method PUT -http_persistent 1
	-hls_segment_filename "$INGEST?cid=$STREAM_KEY&copy=0&file=seg%d.m4s"
)
[ "$SEGMENT_TYPE" = fmp4 ] &&
	HLS+=(-hls_fmp4_init_filename "$INGEST?cid=$STREAM_KEY&copy=0&file=init.mp4")
[ "$SEGMENT_TYPE" = mpegts ] &&
	HLS=("${HLS[@]/seg%d.m4s/seg%d.ts}")
HLS+=("$INGEST?cid=$STREAM_KEY&copy=0&file=stream.m3u8")

# YouTube rejects a video-only ingest, so a silent AAC track rides along.
SILENCE=(-f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100)

# Raw OBU carries no timestamps, so the muxer reconstructs them at a fixed rate;
# MPEG-TS carries its own, but a capture restart resets them, hence igndts+genpts.
if [ "$FEED_FORMAT" = obu ]; then
	FEED_IN=(-fflags +genpts -framerate "$FPS" -f obu -i)
else
	FEED_IN=(-fflags +genpts+igndts -f mpegts -i)
fi

echo "streaming $KMS_DEVICE via $ENCODER -> YouTube HLS. ctrl-c to stop."

# --- capture and muxing split across a FIFO ------------------------------------
# ffmpeg exits when the scanned-out framebuffer disappears (TTY <-> compositor
# switch). Keeping the muxer in its own process, fed over a FIFO, means only the
# capture half restarts and the YouTube session stays up across the switch.
WORKDIR="$(mktemp -d /run/stream-display.XXXXXX)"
chmod 700 "$WORKDIR"
FIFO="$WORKDIR/feed.$FEED_FORMAT"
mkfifo -m 600 "$FIFO"

# Hold the FIFO open from the shell itself; without this the muxer sees EOF on every
# capture restart and tears the whole stream down. The open must be read-write: a
# write-only open blocks until a reader shows up, and the reader is started below.
# Both children get 9>&- so this shell stays the only holder -- otherwise the muxer
# inherits the write end, holds the FIFO open against itself and never sees EOF.
exec 9<>"$FIFO"

cleanup() {
	trap - EXIT INT TERM
	exec 9>&-
	[ -n "${MUX_PID:-}" ] && kill "$MUX_PID" 2>/dev/null || true
	[ -n "${CAP_PID:-}" ] && kill "$CAP_PID" 2>/dev/null || true
	wait 2>/dev/null || true
	rm -rf "$WORKDIR"
}
trap cleanup EXIT INT TERM

"${FFMPEG[@]}" -hide_banner -loglevel warning \
	"${FEED_IN[@]}" "$FIFO" "${SILENCE[@]}" \
	-map 0:v:0 -map 1:a:0 -c:v copy -c:a aac -b:a 128k -shortest \
	"${HLS[@]}" 9>&- &
MUX_PID=$!

(
	while :; do
		"${FFMPEG[@]}" -hide_banner -loglevel warning \
			"${CAPTURE_IN[@]}" "${CAPTURE_OUT[@]}" -f "$FEED_FORMAT" - >"$FIFO" || true
		kill -0 "$MUX_PID" 2>/dev/null || exit 0
		echo "capture ended (VT switch?) -- restarting in 1s" >&2
		sleep 1
	done
) 9>&- &
CAP_PID=$!

wait "$MUX_PID"
