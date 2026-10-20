import SwiftUI

struct HomeDashboardView: View {
    @EnvironmentObject var playerManager: AudioPlayerManager
    @State private var dashboardData = DeezerDashboardData()
    @State private var isLoading = true
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                // Header Branding
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Puki Music")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.pukiAmber, .pukiCoral, .pukiMagenta],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        
                        Text("Dengarkan lagu tanpa batas iklan")
                            .font(.system(size: 13))
                            .foregroundColor(.pukiTextSecondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                            .tint(.pukiCoral)
                            .padding(.vertical, 40)
                        Spacer()
                    }
                } else {
                    // Trending Tracks Carousel
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Lagu Terpopuler")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 14) {
                                ForEach(dashboardData.topTracks) { dTrack in
                                    trackCard(dTrack)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    
                    // Top Albums
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Album Teratas")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 14) {
                                ForEach(dashboardData.topAlbums) { album in
                                    albumCard(album)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }
            }
            .padding(.bottom, 140)
        }
        .task {
            loadDashboard()
        }
    }
    
    private func loadDashboard() {
        Task {
            do {
                let data = try await DeezerService.shared.getDashboardCharts()
                await MainActor.run {
                    self.dashboardData = data
                    self.isLoading = false
                }
            } catch {
                await MainActor.run { self.isLoading = false }
            }
        }
    }
    
    private func trackCard(_ dTrack: DeezerTrack) -> some View {
        Button(action: {
            let track = Track(
                id: "\(dTrack.id)",
                title: dTrack.title,
                artist: dTrack.artistName,
                durationSeconds: dTrack.durationSeconds,
                thumbnailUrl: dTrack.coverUrl,
                streamUrl: dTrack.previewUrl
            )
            playerManager.play(track: track)
        }) {
            VStack(alignment: .leading, spacing: 8) {
                AsyncImage(url: URL(string: dTrack.coverUrl)) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Color.pukiCardElevated
                }
                .frame(width: 140, height: 140)
                .cornerRadius(12)
                .shadow(color: Color.pukiGlowSunset.opacity(0.25), radius: 8, x: 0, y: 4)
                
                Text(dTrack.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(width: 140, alignment: .leading)
                
                Text(dTrack.artistName)
                    .font(.system(size: 11))
                    .foregroundColor(.pukiTextSecondary)
                    .lineLimit(1)
                    .frame(width: 140, alignment: .leading)
            }
        }
    }
    
    private func albumCard(_ album: DeezerAlbum) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: URL(string: album.coverUrl)) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                Color.pukiCardElevated
            }
            .frame(width: 130, height: 130)
            .cornerRadius(12)
            .shadow(color: Color.pukiGlowMagenta.opacity(0.2), radius: 8, x: 0, y: 4)
            
            Text(album.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(width: 130, alignment: .leading)
            
            Text(album.artistName)
                .font(.system(size: 11))
                .foregroundColor(.pukiTextSecondary)
                .lineLimit(1)
                .frame(width: 130, alignment: .leading)
        }
    }
}

// MARK: - Search Tab
struct SearchTabView: View {
    @State private var query = ""
    @State private var trackResults: [DeezerTrack] = []
    @State private var albumResults: [DeezerAlbum] = []
    @State private var selectedFilter: Int = 0 // 0: Semua, 1: Lagu, 2: Album
    @State private var isSearching = false
    @EnvironmentObject var playerManager: AudioPlayerManager
    
    private let filters = ["Semua", "Lagu", "Album"]
    
    var body: some View {
        VStack(spacing: 12) {
            // Search Input Field
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.pukiTextSecondary)
                
                TextField("Cari lagu, artis, atau album...", text: $query)
                    .foregroundColor(.white)
                    .onSubmit { performSearch() }
                
                if !query.isEmpty {
                    Button(action: {
                        query = ""
                        trackResults = []
                        albumResults = []
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.pukiTextSecondary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.pukiCardElevated)
            .cornerRadius(12)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            // Filter Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0..<filters.count, id: \.self) { idx in
                        Button(action: { selectedFilter = idx }) {
                            Text(filters[idx])
                                .font(.system(size: 13, weight: selectedFilter == idx ? .bold : .medium))
                                .foregroundColor(selectedFilter == idx ? .white : .pukiTextSecondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(selectedFilter == idx ? Color.pukiCoral : Color.pukiCard)
                                .cornerRadius(20)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            
            if isSearching {
                Spacer()
                ProgressView().tint(.pukiCoral)
                Spacer()
            } else if trackResults.isEmpty && albumResults.isEmpty && !query.isEmpty {
                Spacer()
                Text("Tidak ada hasil ditemukan")
                    .foregroundColor(.pukiTextSecondary)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Section Album Terkait (jika ada dan filter Semua atau Album)
                        if (selectedFilter == 0 || selectedFilter == 2) && !albumResults.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Album Terkait")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 20)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 14) {
                                        ForEach(albumResults) { album in
                                            VStack(alignment: .leading, spacing: 6) {
                                                AsyncImage(url: URL(string: album.coverUrl)) { img in
                                                    img.resizable().scaledToFill()
                                                } placeholder: {
                                                    Color.pukiCardElevated
                                                }
                                                .frame(width: 120, height: 120)
                                                .cornerRadius(10)
                                                
                                                Text(album.title)
                                                    .font(.system(size: 13, weight: .semibold))
                                                    .foregroundColor(.white)
                                                    .lineLimit(1)
                                                    .frame(width: 120, alignment: .leading)
                                                
                                                Text(album.artistName)
                                                    .font(.system(size: 11))
                                                    .foregroundColor(.pukiTextSecondary)
                                                    .lineLimit(1)
                                                    .frame(width: 120, alignment: .leading)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                }
                            }
                        }
                        
                        // Section Lagu Terkait (jika filter Semua atau Lagu)
                        if (selectedFilter == 0 || selectedFilter == 1) && !trackResults.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Lagu")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 20)
                                
                                ForEach(trackResults) { dTrack in
                                    Button(action: {
                                        let track = Track(
                                            id: "\(dTrack.id)",
                                            title: dTrack.title,
                                            artist: dTrack.artistName,
                                            durationSeconds: dTrack.durationSeconds,
                                            thumbnailUrl: dTrack.coverUrl,
                                            streamUrl: dTrack.previewUrl
                                        )
                                        playerManager.play(track: track)
                                    }) {
                                        HStack(spacing: 12) {
                                            AsyncImage(url: URL(string: dTrack.coverUrl)) { img in
                                                img.resizable().scaledToFill()
                                            } placeholder: {
                                                Color.pukiCardElevated
                                            }
                                            .frame(width: 50, height: 50)
                                            .cornerRadius(8)
                                            
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(dTrack.title)
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundColor(.white)
                                                    .lineLimit(1)
                                                
                                                Text("\(dTrack.artistName) • \(dTrack.albumTitle)")
                                                    .font(.system(size: 12))
                                                    .foregroundColor(.pukiTextSecondary)
                                                    .lineLimit(1)
                                            }
                                            Spacer()
                                        }
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 120) // Safe padding for mini player
                }
            }
        }
        .background(Color.pukiBackground)
    }
    
    private func performSearch() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        isSearching = true
        Task {
            async let tracksReq = DeezerService.shared.searchTracks(query: q)
            async let albumsReq = DeezerService.shared.searchAlbums(query: q)
            
            let tracks = (try? await tracksReq) ?? []
            let albums = (try? await albumsReq) ?? []
            
            await MainActor.run {
                self.trackResults = tracks
                self.albumResults = albums
                self.isSearching = false
            }
        }
    }
}

// MARK: - Library Tab
struct LibraryTabView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Koleksi Musik")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 16)
            
            VStack(spacing: 12) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 48))
                    .foregroundColor(.pukiCoral)
                
                Text("Belum Ada Playlist Tersimpan")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("Lagu favorit dan unduhan offline akan muncul di sini.")
                    .font(.system(size: 13))
                    .foregroundColor(.pukiTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .padding(.top, 80)
            
            Spacer()
        }
        .background(Color.pukiBackground)
    }
}

// MARK: - Settings Tab
struct SettingsTabView: View {
    @State private var showingFilePicker = false
    @State private var showingExportSheet = false
    @State private var exportText: String = ""
    @State private var importMessage: String = ""
    @State private var showingAlert = false
    
    var body: some View {
        List {
            Section(header: Text("TENTANG APLIKASI").foregroundColor(.pukiTextSecondary)) {
                HStack {
                    Text("Versi Aplikasi")
                    Spacer()
                    Text("1.0.3 (iOS Native)")
                        .foregroundColor(.pukiCoral)
                }
                HStack {
                    Text("Build Target")
                    Spacer()
                    Text("iOS 16+ / iPhone 12 Pro Max")
                        .foregroundColor(.pukiTextSecondary)
                }
                HStack {
                    Text("Audio Backend")
                    Spacer()
                    Text("AVPlayer + Deezer / YouTube CDN")
                        .foregroundColor(.pukiTextSecondary)
                }
            }
            .listRowBackground(Color.pukiCard)
            
            Section(header: Text("MIGRASI DATA ANTAR-EKOSISTEM").foregroundColor(.pukiTextSecondary)) {
                Button(action: {
                    showingFilePicker = true
                }) {
                    HStack {
                        Image(systemName: "square.and.arrow.down.fill")
                            .foregroundColor(.pukiAmber)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Impor Cadangan dari Android")
                                .foregroundColor(.white)
                                .font(.system(size: 15, weight: .semibold))
                            Text("Muat file JSON backup dari Puki Music Android")
                                .foregroundColor(.pukiTextSecondary)
                                .font(.system(size: 12))
                        }
                    }
                }
                
                Button(action: {
                    if let exported = LocalMusicStore.shared.exportBackupJson() {
                        exportText = exported
                        showingExportSheet = true
                    }
                }) {
                    HStack {
                        Image(systemName: "square.and.arrow.up.fill")
                            .foregroundColor(.pukiCoral)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ekspor Cadangan ke File JSON")
                                .foregroundColor(.white)
                                .font(.system(size: 15, weight: .semibold))
                            Text("Simpan playlist & favorit untuk dipindah ke Android/PC")
                                .foregroundColor(.pukiTextSecondary)
                                .font(.system(size: 12))
                        }
                    }
                }
            }
            .listRowBackground(Color.pukiCard)
            
            Section(header: Text("STREAMING & KUALITAS").foregroundColor(.pukiTextSecondary)) {
                HStack {
                    Text("Kualitas Streaming")
                    Spacer()
                    Text("Tinggi (High Quality 320kbps)")
                        .foregroundColor(.pukiTextSecondary)
                }
                HStack {
                    Text("Lirik Otomatis (LRCLIB)")
                    Spacer()
                    Text("Aktif")
                        .foregroundColor(.pukiCoral)
                }
            }
            .listRowBackground(Color.pukiCard)
        }
        .scrollContentBackground(.hidden)
        .background(Color.pukiBackground)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.json, .plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    if url.startAccessingSecurityScopedResource() {
                        defer { url.stopAccessingSecurityScopedResource() }
                        if let str = try? String(contentsOf: url, encoding: .utf8) {
                            let res = LocalMusicStore.shared.importBackupJson(str)
                            importMessage = "Berhasil memuat \(res.favoritesCount) lagu favorit dan \(res.playlistsCount) playlist dari cadangan Android!"
                            showingAlert = true
                        }
                    }
                }
            case .failure(let err):
                importMessage = "Gagal membaca file: \(err.localizedDescription)"
                showingAlert = true
            }
        }
        .alert("Migrasi Data", isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importMessage)
        }
        .sheet(isPresented: $showingExportSheet) {
            ShareSheet(activityItems: [exportText])
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}


// MARK: - FullScreen Player View
struct FullScreenPlayerView: View {
    let onLyricsTap: () -> Void
    @EnvironmentObject var playerManager: AudioPlayerManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            Color.pukiBackground.ignoresSafeArea()
            
            if let track = playerManager.currentTrack {
                VStack(spacing: 24) {
                    // Header dismiss
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                        }
                        Spacer()
                        Text("Sedang Memutar")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.pukiTextSecondary)
                        Spacer()
                        Button(action: onLyricsTap) {
                            Image(systemName: "quote.bubble.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.pukiCoral)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    
                    Spacer()
                    
                    // Big Artwork
                    AsyncImage(url: URL(string: track.thumbnailUrl)) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Color.pukiCardElevated
                    }
                    .frame(width: 300, height: 300)
                    .cornerRadius(16)
                    .shadow(color: Color.pukiMagenta.opacity(0.3), radius: 20, x: 0, y: 10)
                    
                    Spacer()
                    
                    // Title & Artist
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        Text(track.artist)
                            .font(.system(size: 15))
                            .foregroundColor(.pukiTextSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28)
                    
                    // Slider
                    VStack(spacing: 6) {
                        Slider(
                            value: Binding(
                                get: { playerManager.currentTime },
                                set: { playerManager.seek(to: $0) }
                            ),
                            in: 0...max(playerManager.duration, 1)
                        )
                        .tint(.pukiRedAccent)
                        
                        HStack {
                            Text(formatTime(playerManager.currentTime))
                                .font(.system(size: 12))
                                .foregroundColor(.pukiTextSecondary)
                            Spacer()
                            Text(formatTime(playerManager.duration))
                                .font(.system(size: 12))
                                .foregroundColor(.pukiTextSecondary)
                        }
                    }
                    .padding(.horizontal, 28)
                    
                    // Controls
                    HStack(spacing: 44) {
                        Button(action: { playerManager.playPrevious() }) {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 26))
                                .foregroundColor(.white)
                        }
                        
                        Button(action: { playerManager.togglePlayPause() }) {
                            ZStack {
                                if playerManager.isBuffering {
                                    ProgressView()
                                        .tint(.pukiCoral)
                                        .scaleEffect(1.5)
                                } else {
                                    Image(systemName: playerManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                        .font(.system(size: 64))
                                        .foregroundColor(.pukiCoral)
                                }
                            }
                            .frame(width: 64, height: 64)
                        }
                        
                        Button(action: { playerManager.playNext() }) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 26))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.bottom, 36)
                }
            }
        }
    }
    
    private func formatTime(_ sec: Double) -> String {
        let m = Int(sec) / 60
        let s = Int(sec) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Lyrics Sheet View
struct LyricsSheetView: View {
    @EnvironmentObject var playerManager: AudioPlayerManager
    @Environment(\.dismiss) var dismiss
    @State private var lyrics: LyricsResult?
    @State private var isLoading = true
    
    var body: some View {
        ZStack {
            Color.pukiBackground.ignoresSafeArea()
            
            VStack(spacing: 16) {
                // Header
                HStack {
                    Text("Lirik Lagu")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.pukiTextSecondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                
                if isLoading {
                    Spacer()
                    ProgressView().tint(.pukiCoral)
                    Spacer()
                } else if let lrc = lyrics {
                    if lrc.isSynced && !lrc.lines.isEmpty {
                        ScrollViewReader { proxy in
                            ScrollView(showsIndicators: false) {
                                VStack(spacing: 18) {
                                    ForEach(lrc.lines) { line in
                                        let isCurrent = isLineActive(line, allLines: lrc.lines)
                                        Text(line.text)
                                            .font(.system(size: isCurrent ? 22 : 17, weight: isCurrent ? .bold : .medium))
                                            .foregroundColor(isCurrent ? .pukiAmber : .pukiTextSecondary.opacity(0.6))
                                            .multilineTextAlignment(.center)
                                            .id(line.id)
                                    }
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 32)
                            }
                        }
                    } else if let plain = lrc.plainLyrics {
                        ScrollView {
                            Text(plain)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                                .lineSpacing(8)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 32)
                        }
                    }
                } else {
                    Spacer()
                    Text("Lirik tidak tersedia untuk lagu ini.")
                        .foregroundColor(.pukiTextSecondary)
                    Spacer()
                }
            }
        }
        .task {
            if let track = playerManager.currentTrack {
                self.lyrics = await LyricsService.shared.getLyrics(track: track)
                self.isLoading = false
            }
        }
    }
    
    private func isLineActive(_ line: LyricLine, allLines: [LyricLine]) -> Bool {
        let currentMs = Int64(playerManager.currentTime * 1000)
        guard currentMs >= line.timeMs else { return false }
        if let idx = allLines.firstIndex(where: { $0.id == line.id }),
           idx + 1 < allLines.count {
            return currentMs < allLines[idx + 1].timeMs
        }
        return true
    }
}
