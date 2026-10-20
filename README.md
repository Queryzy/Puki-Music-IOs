# Puki Music iOS

Aplikasi Native Audio Streaming untuk iOS (Target: iPhone 12 Pro Max / iOS 16+) dibangun dengan SwiftUI dan AVPlayer.

## Fitur Utama:
- **UI/UX Puki Midnight Glow**: Tema gelap `#0C0C14` dengan gradien Sunset Amber, Coral Pink, dan Magenta.
- **YouTube Music Style Mini Player**: Garis merah tipis seekbar persis YouTube Music di atas bar kontrol.
- **Audio Engine**: AVPlayer native dengan dukungan background playback (`UIBackgroundModes: audio`).
- **Lockscreen & Dynamic Island**: Integrasi penuh `MPNowPlayingInfoCenter` & `MPRemoteCommandCenter` (scrubbing, cover art, dan kontrol pause/next dari lockscreen iPhone).
- **Resolver**: Deezer API Chart/Search + LRCLIB Synchronized Lyrics.

## Build ke IPA:
Pipeline otomatis via GitHub Actions (`.github/workflows/build-ios.yml`) menggunakan macOS 14 runner untuk meng-generate `Puki-Music.ipa` unsigned yang siap di-sign oleh SideStore atau Sideloadly.
