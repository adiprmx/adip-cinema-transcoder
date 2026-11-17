#!/usr/bin/env bash
# Unggah hasil transcode ke Backblaze B2 lewat rclone.
#
# Pakai:
#   upload-b2.sh <dir_hasil> <bucket> <prefix_tujuan>
#
# Contoh:
#   upload-b2.sh out nama-bucket films/bougainvillea-2024/720p
#
# Kredensial dibaca dari environment (di GitHub Actions, dari secrets repo):
#   B2_KEY_ID    keyID application key B2
#   B2_APP_KEY   application key B2
#
# Skrip ini berhenti dengan pesan jelas bila salah satu variabel kosong,
# supaya kegagalan karena secrets belum diisi tidak terlihat seperti
# kegagalan jaringan atau kegagalan rclone.
set -euo pipefail

SRC="$1"
BUCKET="$2"
DEST="$3"

if [ -z "${B2_KEY_ID:-}" ] || [ -z "${B2_APP_KEY:-}" ]; then
  echo "ERROR: secrets B2 belum diisi." >&2
  echo "Isi dulu di repo ini: Settings > Secrets and variables > Actions," >&2
  echo "lalu tambah B2_KEY_ID dan B2_APP_KEY (dari application key akun B2)," >&2
  echo "dan B2_BUCKET (nama bucket). Akun B2 dibuat tanpa kartu di backblaze.com." >&2
  echo "Transcode sudah selesai dan file ada di runner ini, tapi tidak ada" >&2
  echo "tujuan unggah yang bisa dipakai. Jalankan ulang workflow sesudah" >&2
  echo "secrets diisi." >&2
  exit 1
fi

if [ -z "$BUCKET" ]; then
  echo "ERROR: nama bucket kosong. Isi secret B2_BUCKET di repo ini." >&2
  exit 1
fi

export RCLONE_CONFIG_B2_TYPE=b2
export RCLONE_CONFIG_B2_ACCOUNT="$B2_KEY_ID"
export RCLONE_CONFIG_B2_KEY="$B2_APP_KEY"

echo "Unggah $SRC -> b2:$BUCKET/$DEST"
rclone copy --transfers 8 --checkers 8 --retries 3 \
  --stats 30s --stats-one-line \
  "$SRC" "b2:$BUCKET/$DEST"

echo "Unggah selesai."
rclone ls "b2:$BUCKET/$DEST" | head -20
echo "Total file di tujuan: $(rclone ls "b2:$BUCKET/$DEST" | wc -l)"
