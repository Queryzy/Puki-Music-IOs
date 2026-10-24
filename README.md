# 🍏 Puki Music iOS

<div align="center">

![Puki Music iOS](https://raw.githubusercontent.com/Queryzy/Puki-Music-IOs/main/PukiMusic/Assets.xcassets/AppLogo.imageset/app_logo.png)

**Native iOS Music Streaming Player (SwiftUI, AVPlayer, Midnight Glow UI & Zero-Knowledge E2EE Cross-Device Sync)**

[![Platform](https://img.shields.io/badge/Platform-iOS_16.0+-blue.svg)](https://apple.com/ios)
[![Language](https://img.shields.io/badge/Language-Swift_5.9-orange.svg)](https://swift.org)
[![UI](https://img.shields.io/badge/UI-SwiftUI-red.svg)](https://developer.apple.com/xcode/swiftui/)
[![Audio Engine](https://img.shields.io/badge/Audio-AVPlayer_/_AVAudioSession-purple.svg)](https://developer.apple.com/av-foundation/)
[![SideStore](https://img.shields.io/badge/Install-SideStore_/_AltStore-brightgreen.svg)](https://sidestore.io)

</div>

---

## 🌐 Ekosistem Puki Music
Puki Music hadir dalam ekosistem multi-platform mandiri yang saling terhubung:
* 🍏 **iOS Client (SwiftUI / AVPlayer)**: [Queryzy/Puki-Music-IOs](https://github.com/Queryzy/Puki-Music-IOs)
* 🤖 **Android Client (Jetpack Compose / ExoPlayer)**: [Queryzy/Puki-Music-Android](https://github.com/Queryzy/Puki-Music-Android)
* ⚡ **Blind Ledger Sync Relay (Workers & Docker)**: [Queryzy/Puki-Sync-Relay](https://github.com/Queryzy/Puki-Sync-Relay)

---

## ✨ Fitur Utama
* **Puki Midnight Glow Design System**: Tema gelap modern (`#0C0C14`) dengan aksen gradien Sunset Amber, Coral Pink, dan Magenta.
* **YouTube Music Style Mini Player**: Mini player mengambang dengan garis merah tipis seekbar persis YouTube Music yang responsif terhadap scrubbing.
* **Lockscreen & Dynamic Island Integration**: Kontrol audio penuh dari layar kunci iPhone via `MPNowPlayingInfoCenter` dan `MPRemoteCommandCenter` (album artwork retina, seekbar scrubbing, play/pause/skip).
* **Audio Engine Tangguh**: Dibangun di atas `AVPlayer` native dengan dukungan penuh pemutaran latar belakang saat layar iPhone terkunci (`UIBackgroundModes: audio`).
* **Karaoke Synchronized Lyrics**: Lirik tersinkronisasi real-time via LRCLIB dengan auto-scroll dan tap baris lirik untuk lompat ke detik yang dipilih.
* **Multi-Source Audio Resolution**: Integrasi katalog Deezer API Charts & Pencarian dengan fallback resolver audio stream berkecepatan tinggi.
* **Zero-Knowledge E2EE Cross-Device Sync**: Sinkronisasi riwayat musik, pencarian, dan lagu favorit 1:1 antara iPhone & Android secara terenkripsi ujung-ke-ujung.

---

## 🔐 Mekanisme & Arsitektur Sinkronisasi E2EE
Puki Music iOS mengimplementasikan protokol **Zero-Knowledge Blind Ledger**:
1. **Client-Side AES-256-GCM**: Seluruh mutasi data dienkripsi langsung di perangkat menggunakan `CryptoKit`. Server relay hanya melihat ciphertext acak.
2. **Visual QR Pairing**: Pertukaran kunci rahasia dilakukan secara offline antar kamera perangkat (`pukisync://pair?vault=...&key=...`). Kunci dekripsi tidak pernah lewat melalui server relay.
3. **HMAC-SHA256 Authentication**: Setiap transaksi push dan pull ditandatangani secara kriptografis dengan replay-attack protection 5 menit.
4. **Non-Destructive Set Union (1:1 Sync)**: Lagu favorit dan riwayat lama digabung secara cerdas tanpa risiko data lokal tertimpa atau hilang.

---

## 📲 Cara Install di iPhone (Sideload)

### Cara 1: Menggunakan SideStore (Otomatis & Tanpa Komputer Tiap Minggu)
1. Pasang **[SideStore](https://sidestore.io)** di iPhone Anda.
2. Buka SideStore > Tab **Sources** > Tekan tombol `+` di kanan atas.
3. Masukkan URL Sumber Komunitas Puki Music:
   ```
   https://raw.githubusercontent.com/Queryzy/Puki-Music-IOs/main/apps.json
   ```
4. Buka tab **Apps** di SideStore, cari **Puki Music**, lalu tekan **INSTALL**.
5. Aplikasi akan terpasang dan dapat diperbarui langsung dari dalam SideStore.

### Cara 2: Sideload IPA Manual (AltStore / Sideloadly / TrollStore)
1. Buka halaman **[Releases](https://github.com/Queryzy/Puki-Music-IOs/releases)** di GitHub.
2. Unduh file `Puki-Music.ipa` versi terbaru.
3. Buka **Sideloadly** atau **AltStore** di komputer, hubungkan iPhone, lalu seret file `Puki-Music.ipa` untuk memasang dengan Apple ID Anda.

---

## 🛠️ Build dari Source Code & CI/CD Pipeline
Repository ini dilengkapi pipeline otomatis **GitHub Actions** (`.github/workflows/build-ios.yml`):
* Setiap push ke branch `main` akan menjalankan runner **macOS 14 (Xcode 15.4)**.
* Pipeline melakukan kompilasi proyek SwiftUI via `xcodebuild`, menyematkan izin kamera (`NSCameraUsageDescription`), dan mem-package biner ke dalam format unsigned `.ipa`.
* File IPA otomatis diunggah ke GitHub Releases dan memperbarui file manifest SideStore `apps.json`.

---

## ⚙️ Cara Menghubungkan Sinkronisasi (Pairing)
1. Buka tab **Pengaturan** di Puki Music iOS.
2. Pada bagian **Sinkronisasi Antar-Perangkat**, masukkan URL Relay (contoh: `https://puki-sync.diylabs.top` atau self-hosted Anda).
3. Jika menghubungkan dari Android:
   * Tekan tombol **Pindai QR**.
   * Arahkan kamera iPhone ke QR Code yang ditampilkan di layar Android.
4. Atau tekan **Buat Kunci Baru** untuk membuat vault baru di iPhone, lalu scan QR tersebut menggunakan Android.
5. Tekan **Sinkronkan Sekarang** untuk menyinkronkan seluruh lagu favorit dan riwayat secara instan.

---

## 📄 Lisensi
Didistribusikan di bawah lisensi MIT. Lihat file `LICENSE` untuk rincian lengkap.
