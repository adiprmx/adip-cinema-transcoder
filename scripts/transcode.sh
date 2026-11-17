#!/usr/bin/env bash
# Transcode satu file video menjadi HLS (segmen 6 detik) + MP4 progresif.
#
# Pakai:
#   transcode.sh <input> <outdir> <quality> <width> <height> <video_bitrate> [segment_seconds]
#
# Contoh:
#   transcode.sh input/source.mkv out 720p 1280 720 2500k 6
#
# Hasil di <outdir>:
#   stream_<quality>.m3u8   playlist HLS kualitas ini
#   seg_<quality>_NNN.ts    segmen video, masing-masing <segment_seconds> detik
#   <quality>.mp4           MP4 progresif, dibuat dari segmen yang sama
#                           (salin ulang tanpa encode kedua, jadi cepat)
#
# Audio selalu diubah ke AAC stereo 128 kbps. Ini sengaja: trek AC3 5.1
# di file MKV tidak bersuara di Chrome, dan konversi ke AAC menghilangkan
# masalah itu di hasil akhir.
#
# Skrip ini juga jalan di Termux (transcoder cadangan), bukan cuma di
# GitHub Actions. Syaratnya cuma ffmpeg terpasang.
set -euo pipefail

INPUT="$1"
OUT="$2"
QUALITY="$3"
W="$4"
H="$5"
VB="$6"
SEG="${7:-6}"

mkdir -p "$OUT"

# VB berbentuk "2500k". Bufsize = 2x bitrate video.
VB_NUM="${VB%k}"
BUFSIZE="$(( VB_NUM * 2 ))k"

echo "Transcode $INPUT -> HLS $QUALITY (${W}x${H}, video $VB, audio AAC 128k, segmen ${SEG} detik)"

ffmpeg -hide_banner -loglevel error -y -i "$INPUT" \
  -vf "scale=${W}:${H}:force_original_aspect_ratio=decrease,pad=${W}:${H}:(ow-iw)/2:(oh-ih)/2" \
  -c:v libx264 -preset veryfast -b:v "$VB" -maxrate "$VB" -bufsize "$BUFSIZE" \
  -c:a aac -b:a 128k -ac 2 \
  -f hls -hls_time "$SEG" -hls_playlist_type vod \
  -hls_segment_filename "$OUT/seg_${QUALITY}_%03d.ts" \
  "$OUT/stream_${QUALITY}.m3u8"

echo "HLS selesai: $(ls "$OUT"/seg_*.ts | wc -l) segmen"

# MP4 progresif dari playlist yang sama. -c copy berarti tidak ada
# encode kedua, jadi langkah ini hanya menyambung segmen.
ffmpeg -hide_banner -loglevel error -y -i "$OUT/stream_${QUALITY}.m3u8" \
  -c copy -movflags +faststart "$OUT/${QUALITY}.mp4"

echo "MP4 selesai: $OUT/${QUALITY}.mp4"
