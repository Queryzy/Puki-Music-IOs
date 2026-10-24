# PRD: Puki Music iOS (Client Application & E2EE Sync)

## 1. Overview & Objective
- **Nama Proyek**: Puki Music iOS (`puki-music-ios`)
- **Tujuan**: Pemutar musik iOS native (SwiftUI + AVPlayer) dengan performa tinggi, zero tracking, background audio, dan sinkronisasi data antar-perangkat berbasis Zero-Knowledge E2EE tanpa dependensi library pihak ketiga (0 External Pods / SPM).
- **Format Penyimpanan**: Local-First `UserDefaults` (`LocalMusicStore.swift`) dengan state reaktif SwiftUI (`@Published`).

---

## 2. Arsitektur Komponen Sync iOS

### 2.1. Layanan Baru: `PukiMusic/Services/`
1. **`SyncCrypto.swift`**:
   - Memanfaatkan framework resmi Apple **`CryptoKit`**.
   - Penurunan kunci simetris `K_enc` dan `K_auth` via HMAC-SHA256.
   - Enkripsi dan dekripsi pesan menggunakan `AES.GCM.seal` dan `AES.GCM.open`.
   - Perhitungan header tanda tangan request via `HMAC<SHA256>`.
2. **`SyncManager.swift`**:
   - `ObservableObject` singleton pengelola siklus sinkronisasi.
   - Pengiriman HTTP asinkron via `URLSession.shared`.
   - Timer polling 30 detik selama aplikasi berstatus `scenePhase == .active`.
   - Hook penarikan data instan saat menerima notifikasi `UIApplication.willEnterForegroundNotification`.
   - Antrean persisten `sync_outbox` pada `UserDefaults`.
3. **`QRViews.swift` (di folder `PukiMusic/Views/`)**:
   - **Generator QR**: Menggunakan `CIFilter(name: "CIQRCodeGenerator")` bawaan framework `CoreImage`.
   - **Pemindai QR**: `UIViewControllerRepresentable` membungkus session `AVCaptureSession` dan `AVCaptureMetadataOutput` untuk scanning instan dari viewfinder kamera.

---

## 3. Hooking Data di `LocalMusicStore.swift`
- **Outgoing Events**:
  - `recordPlay(track:)` -> Menembak event `RECORD_PLAY`.
  - `toggleFavorite(track:)` -> Menembak event `TOGGLE_FAVORITE`.
  - `addRecentSearch(_:)` -> Menembak event `ADD_SEARCH`.
  - `savePlaylists()` -> Menembak event `UPDATE_PLAYLIST`.
- **Incoming Events (`applyRemoteSyncEvent`)**:
  - Menerima payload JSON hasil dekripsi `SyncManager`.
  - Memperbarui array `@Published var favorites`, `@Published var playlists`, `@Published var recentSearches`, dan `@Published var playHistory`.
  - UI SwiftUI langsung ter-render ulang secara otomatis dan mulus.

---

## 4. Rincian Tiket Pengerjaan iOS (Task Breakdown)

| Tiket | Deskripsi Pekerjaan | Kriteria Penerimaan (Acceptance Criteria) |
| :--- | :--- | :--- |
| **T-IOS-1** | Penambahan deklarasi izin `NSCameraUsageDescription` pada `PukiMusic/Info.plist`. | Aplikasi tidak crash saat inisialisasi modul kamera pemindai QR Code. |
| **T-IOS-2** | Pembuatan modul `PukiMusic/Services/SyncCrypto.swift` berbasis `CryptoKit` (AES-256-GCM + HMAC-SHA256). | Kriptografi 100% kompatibel lintas platform (dapat mendekripsi ciphertext yang dihasilkan oleh Android SDK). |
| **T-IOS-3** | Pembuatan modul `PukiMusic/Services/SyncManager.swift` (URLSession networking, polling loop, outbox persistent, foreground hook). | Engine mampu melakukan handshake `/vault/init`, push delta event terenkripsi, dan pull event baru dari Relay D1. |
| **T-IOS-4** | Patching `LocalMusicStore.swift` untuk menyematkan trigger push event ke `SyncManager` dan listener remote event masuk. | Data riwayat pencarian, lagu favorit, dan playlist baru yang diterima langsung memperbarui model lokal dan UI SwiftUI. |
| **T-IOS-5** | Integrasi antarmuka pada `Screens.swift` (`SettingsTabView`): Tombol "Sinkronisasi Perangkat", sheet generator QR code, dan sheet kamera scanner. | iPhone dapat menampilkan QR Code pairing (`puki://sync?...`) dan kamera dapat membaca QR dari perangkat Android. |
| **T-IOS-6** | Pengujian integrasi iOS: Verifikasi kelancaran audio background saat sync aktif dan verifikasi bahwa storage lokal tidak saling timpa data. | Playback audio tidak mengalami drop frame atau pause saat proses sinkronisasi HTTP berlangsung di background. |
