# adip-cinema-transcoder

Repo ini mengubah film menjadi HLS (segmen 6 detik, 3 kualitas) plus
MP4 progresif, memakai GitHub Actions dan ffmpeg. Hasilnya diunggah
langsung ke Backblaze B2. Repo ini bagian dari Adip Cinema v5.

## Kenapa repo publik terpisah

Repo aplikasi Adip Cinema privat. Menit GitHub Actions di repo privat
free tier cuma sekitar 2.000 menit Linux per bulan, dan satu film 2 jam
ke satu kualitas saja makan 2 sampai 4 jam runner. Repo publik dapat
menit runner standar tanpa batas, dan kode transcoder (workflow YAML
plus skrip ffmpeg) tidak mengandung apa pun yang sensitif. Film
sumbernya tidak masuk repo: workflow mengunduh film dari URL yang
diberi saat dispatch, lalu mengunggah segmen kembali ke B2.

## Cara pakai

Buka tab Actions di repo ini, pilih workflow "Transcode to HLS",
tekan "Run workflow", isi parameternya.

| Parameter | Isi |
|---|---|
| film_slug | Slug film, jadi nama folder di B2: `films/<slug>/`. Contoh: `bougainvillea-2024`. Huruf kecil, angka, dan strip saja. |
| source_url | URL video sumber. Bisa URL presigned B2 atau tautan unduh Drive. Kosongkan untuk mode tes. |
| test_seconds | Durasi video sintetis dalam detik, bila source_url kosong. Default 30. |
| upload | `true` untuk mengunggah hasil ke B2. Butuh secrets B2 di repo ini (lihat bawah). Default `false`. |

Mode tes: tiap job membuat video sintetis sendiri (pola `testsrc2`
plus nada 440 Hz) lalu men-transcode-nya. Mode tes tidak butuh file
eksternal dan tidak mengunggah apa pun. Pola testsrc2 penuh detail
acak, jadi ini kasus terberat buat encoder. Film asli di-encode lebih
cepat.

Satu run men-transcode ketiga kualitas sekaligus (tiga job paralel).
Satu film hanya ditranscode satu run pada satu waktu. Run kedua untuk
slug yang sama menunggu sampai run pertama selesai.

## Arsitektur

Tiap job kualitas jalan di runner `ubuntu-24.04` dan melakukan:

1. Pasang ffmpeg dan rclone lewat apt-get. ffmpeg tidak terpasang di
   image runner, jadi langkah ini wajib.
2. Siapkan video sumber: unduh dari `source_url`, atau buat video
   sintetis bila URL kosong.
3. Transcode dengan `scripts/transcode.sh`: H.264 (`libx264`, preset
   veryfast), audio diubah ke AAC stereo 128 kbps, segmen HLS 6 detik,
   lalu MP4 progresif dibuat dari segmen yang sama tanpa encode kedua.
   Audio diubah ke AAC karena trek AC3 5.1 di file MKV tidak bersuara
   di Chrome.
4. Validasi dengan ffprobe di job yang sama: playlist ada dan ditutup
   `#EXT-X-ENDLIST`, segmen pertama ber-codec h264 dengan resolusi
   yang benar, MP4 ada dan punya durasi.
5. Bila `upload=true`, unggah ke B2 lewat `scripts/upload-b2.sh`
   (rclone). Bila secrets B2 kosong, langkah ini berhenti dengan
   pesan yang menjelaskan secrets mana yang belum diisi.
6. Simpan playlist `.m3u8` dan ringkasan JSON sebagai artefak. Segmen
   video tidak masuk artefak (kuota artefak cuma 500 MB).

Job keempat membuat `master.m3u8` dari ketiga playlist kualitas,
lalu mengunggahnya ke B2 di samping folder kualitas.

Tata letak hasil di B2:

```
films/bougainvillea-2024/
  master.m3u8
  360p/stream_360p.m3u8
  360p/seg_360p_000.ts ...
  360p/360p.mp4
  720p/stream_720p.m3u8
  720p/seg_720p_000.ts ...
  720p/720p.mp4
  1080p/stream_1080p.m3u8
  1080p/seg_1080p_000.ts ...
  1080p/1080p.mp4
```

## Secrets B2

Isi di Settings, Secrets and variables, Actions, di repo ini. Repo
ini hanya memakai namanya. Nilainya tidak pernah ditulis di file
mana pun di repo ini.

| Secret | Isi |
|---|---|
| B2_KEY_ID | keyID application key Backblaze B2 |
| B2_APP_KEY | application key Backblaze B2 |
| B2_BUCKET | Nama bucket B2 tujuan unggah |

Status saat README ini ditulis: akun B2 belum dibuat, jadi ketiga
secrets masih kosong dan langkah unggah gagal dengan pesan jelas bila
dijalankan dengan `upload=true`. Itu perilaku yang dirancang, bukan
bug. Akun B2 dibuat tanpa kartu di backblaze.com, dan bucket yang
dipakai adalah bucket privat (bucket publik pertama B2 butuh riwayat
pembayaran).

## Batas dan angka

Semua angka di bawah ini berasal dari pengukuran di laporan riset
Adip Cinema v5 (laporan 10) atau dari dokumentasi resmi GitHub.
Perkiraan diberi label perkiraan.

| Batas | Nilai |
|---|---|
| Satu job | Maks 6 jam, lalu dibatalkan GitHub |
| 720p H.264 veryfast | 0,51x realtime di VM 1,5 CPU. Perkiraan di runner 4 vCPU: 1,5 sampai 2 jam per film 2 jam |
| 1080p H.264 veryfast | 0,23x realtime di VM 1,5 CPU. Perkiraan di runner 4 vCPU: 3 sampai 4,5 jam per film 2 jam |
| VP9 | 0,037x realtime. Satu film 2 jam butuh sekitar 54 jam di VM, belasan jam di runner. Tidak masuk workflow ini |
| AV1 | 0,07x realtime. Satu film 2 jam butuh sekitar 28 jam di VM. Tidak masuk workflow ini |
| Ukuran hasil per film 2 jam | 360p sekitar 1,0 GB, 720p sekitar 2,4 GB, 1080p sekitar 5,5 GB |
| Segmen 6 detik | 1.200 file per kualitas per film 2 jam |
| Artefak Actions | 500 MB. Satu film 1080p saja 11x lipat kuota ini, jadi hasil wajib ke B2 |
| Runner | 4 vCPU, 16 GB RAM (runner standar repo publik) |

Strategi format mengikuti angka di atas: H.264 dulu untuk semua film,
VP9 dan AV1 belakangan dari transcoder lain bila ukuran menjadi
masalah nyata.

## ToS GitHub Actions dan transcoder cadangan

Apakah memakai GitHub Actions untuk transcoding film melanggar
ketentuan layanan GitHub, belum terverifikasi. Ronde riset tidak
membaca klausul ToS yang relevan dan tidak mengklaim apa pun soal
itu. Risiko ini dicatat apa adanya, dan Actions bukan satu-satunya
transcoder.

Cadangannya: ffmpeg di Termux di HP (`pkg install ffmpeg`), memakai
`scripts/transcode.sh` yang sama, lalu unggah segmen ke B2. Batasnya
juga dicatat jujur: HP owner hampir penuh (sisa sekitar 1 GB), jadi
transcode di HP hanya jalan bila film sumber dan hasil disimpan di
tempat lain (kartu SD, USB OTG, atau unggah segmen langsung sesudah
jadi). Server rumah adalah transcoder cadangan kedua, sesudah ada.

## Status uji

Run tes pertama (video sintetis 30 detik, ketiga kualitas, tanpa
unggah B2): belum jalan saat README ini ditulis. Bagian ini
diperbarui sesudah run pertama hijau, dengan tautan ke run-nya.

Transcode film asli (Bougainvillea) belum bisa: file-nya belum ada
di B2 atau Drive dalam bentuk URL yang bisa diakses Actions.
Langkahnya sesudah file tersedia: dispatch workflow dengan
`film_slug=bougainvillea-2024`, `source_url` berisi URL presigned B2
atau tautan unduh Drive file MKV-nya, dan `upload=true` sesudah
secrets B2 diisi.

## Lisensi

GPL-3.0-only. Lihat file LICENSE.
