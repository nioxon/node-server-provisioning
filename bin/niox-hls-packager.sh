#!/usr/bin/env bash
set -e

# ==============================================================================
# NIOX HLS Video Packager & Zero-Buffering Chunk Generator
# Slices MP4/MKV video files into 4-second keyframe-aligned HLS .ts segments
# with master .m3u8 playlist for passenger zero-buffering streaming.
# ==============================================================================

INPUT_FILE="$1"
OUTPUT_DIR="$2"
CHUNK_DURATION="${3:-4}" # Default 4 seconds per chunk

if [ -z "$INPUT_FILE" ] || [ -z "$OUTPUT_DIR" ]; then
  echo "Usage: niox-hls-packager <input_video.mp4> <output_dir> [chunk_duration_sec]"
  echo "Example: niox-hls-packager /media/usb/movie.mp4 /opt/nioxon/media/hls/movies/101 4"
  exit 1
fi

if [ ! -f "$INPUT_FILE" ]; then
  echo "❌ Input file not found: $INPUT_FILE"
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo "▶ Packaging video into zero-buffering HLS chunks ($CHUNK_DURATION sec/chunk)..."
echo "  Source: $INPUT_FILE"
echo "  Destination: $OUTPUT_DIR"

# Keyframe interval (GOP): 30fps * 4s = 120 frames
GOP_SIZE=$(( CHUNK_DURATION * 30 ))

ffmpeg -i "$INPUT_FILE" \
  -c:v libx264 -preset veryfast -profile:v main -crf 22 \
  -g "$GOP_SIZE" -keyint_min "$GOP_SIZE" -sc_threshold 0 \
  -c:a aac -b:a 128k -ar 44100 -ac 2 \
  -f hls \
  -hls_time "$CHUNK_DURATION" \
  -hls_playlist_type vod \
  -hls_flags independent_segments \
  -hls_segment_filename "$OUTPUT_DIR/chunk_%04d.ts" \
  "$OUTPUT_DIR/master.m3u8"

# Set permissions for web server
chown -R www-data:www-data "$OUTPUT_DIR"
chmod -R 775 "$OUTPUT_DIR"

echo "✔ HLS packaging complete! Master playlist: $OUTPUT_DIR/master.m3u8"
