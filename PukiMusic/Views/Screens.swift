import SwiftUI

struct HomeDashboardView: View {
    @EnvironmentObject var playerManager: AudioPlayerManager
    @State private var dashboardData = DeezerDashboardData()
    @State private var isLoading = true
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                // Header Branding (1:1 Android with Logo & Gradient)
                HStack(spacing: 12) {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 38, height: 38)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.pukiCoral.opacity(0.4), lineWidth: 1.5)
                        )
                        .shadow(color: Color.pukiGlowSunset.opacity(0.4), radius: 6, x: 0, y: 2)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text("Puki")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white)
                            Text("Music")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.pukiAmber, .pukiCoral, .pukiMagenta],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        }
                        
                        Text("Dengarkan lagu tanpa batas iklan")
                            .font(.system(size: 12))
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
    @State private var activeAlbum: DeezerAlbum? = nil
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
                        // Section Album Terkait (Tampil List Vertikal ke Bawah persis Android)
                        if (selectedFilter == 0 || selectedFilter == 2) && !albumResults.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: "opticaldisc.fill")
                                        .foregroundColor(.pukiCoral)
                                        .font(.system(size: 14))
                                    Text("ALBUM RESMI TERKAIT (\(albumResults.count))")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.pukiCoral)
                                    Spacer()
                                }
                                .padding(.horizontal, 20)
                                
                                ForEach(albumResults) { album in
                                    Button(action: {
                                        activeAlbum = album
                                    }) {
                                        HStack(spacing: 14) {
                                            AsyncImage(url: URL(string: album.coverUrl)) { img in
                                                img.resizable().scaledToFill()
                                            } placeholder: {
                                                Color.pukiCardElevated
                                            }
                                            .frame(width: 64, height: 64)
                                            .cornerRadius(10)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                            )
                                            
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(album.title)
                                                    .font(.system(size: 15, weight: .bold))
                                                    .foregroundColor(.white)
                                                    .lineLimit(1)
                                                
                                                Text("\(album.artistName)")
                                                    .font(.system(size: 13))
                                                    .foregroundColor(.pukiAmber)
                                                    .lineLimit(1)
                                                
                                                Text("\(album.trackCount > 0 ? "\(album.trackCount) Lagu" : "Album Resmi") • Ketuk untuk buka diskografi")
                                                    .font(.system(size: 11))
                                                    .foregroundColor(.pukiTextSecondary)
                                            }
                                            
                                            Spacer()
                                            
                                            Image(systemName: "chevron.right")
                                                .foregroundColor(.pukiTextSecondary)
                                                .font(.system(size: 13, weight: .semibold))
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(Color.pukiCard)
                                        .cornerRadius(12)
                                        .padding(.horizontal, 20)
                                    }
                                }
                            }
                        }
                        
                        // Section Lagu Terkait (jika filter Semua atau Lagu)
                        if (selectedFilter == 0 || selectedFilter == 1) && !trackResults.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: "music.note")
                                        .foregroundColor(.white)
                                        .font(.system(size: 14))
                                    Text("LAGU")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.white)
                                    Spacer()
                                }
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
                                            .frame(width: 52, height: 52)
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
        .sheet(item: $activeAlbum) { album in
            AlbumDetailSheetView(album: album)
                .environmentObject(playerManager)
                .presentationDetents([.fraction(0.85), .large])
                .presentationDragIndicator(.visible)
        }
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

// MARK: - Album Detail Modal Sheet
struct AlbumDetailSheetView: View {
    let album: DeezerAlbum
    @State private var tracks: [DeezerTrack] = []
    @State private var isLoading = true
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var playerManager: AudioPlayerManager
    
    var body: some View {
        ZStack {
            Color.pukiBackground.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header Sheet
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.pukiTextSecondary)
                    }
                    Spacer()
                    Text("DISKOGRAFI & DAFTAR ALBUM")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.pukiCoral)
                        .tracking(1)
                    Spacer()
                    // Dummy spacer to center title
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.clear)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Album Header Info Card
                        HStack(spacing: 16) {
                            AsyncImage(url: URL(string: album.coverUrl)) { img in
                                img.resizable().scaledToFill()
                            } placeholder: {
                                Color.pukiCardElevated
                            }
                            .frame(width: 84, height: 84)
                            .cornerRadius(12)
                            .shadow(color: Color.pukiGlowMagenta.opacity(0.3), radius: 10, x: 0, y: 4)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(album.title)
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                                
                                Text(album.artistName)
                                    .font(.system(size: 14))
                                    .foregroundColor(.pukiAmber)
                                
                                Text("\(tracks.count > 0 ? "\(tracks.count) Lagu" : "\(album.trackCount) Lagu") • Album Resmi")
                                    .font(.system(size: 12))
                                    .foregroundColor(.pukiTextSecondary)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(Color.pukiCard)
                        .cornerRadius(14)
                        .padding(.horizontal, 20)
                        
                        // Action Buttons: Putar Album
                        if !tracks.isEmpty {
                            Button(action: {
                                playAllAlbumTracks()
                            }) {
                                HStack {
                                    Image(systemName: "shuffle")
                                        .font(.system(size: 15, weight: .bold))
                                    Text("PUTAR SEMUA LAGU")
                                        .font(.system(size: 13, weight: .bold))
                                }
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.pukiAmber)
                                .cornerRadius(10)
                                .padding(.horizontal, 20)
                            }
                        }
                        
                        // Tracks List
                        if isLoading {
                            VStack {
                                Spacer()
                                ProgressView().tint(.pukiCoral)
                                    .scaleEffect(1.2)
                                    .padding(.top, 40)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                        } else if tracks.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "music.note.slash")
                                    .font(.system(size: 32))
                                    .foregroundColor(.pukiTextSecondary)
                                Text("Daftar lagu album tidak ditemukan")
                                    .font(.system(size: 13))
                                    .foregroundColor(.pukiTextSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("DAFTAR LAGU (\(tracks.count))")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.pukiTextSecondary)
                                    .padding(.horizontal, 20)
                                
                                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, t in
                                    Button(action: {
                                        let selectedTrack = Track(
                                            id: "\(t.id)",
                                            title: t.title,
                                            artist: t.artistName,
                                            durationSeconds: t.durationSeconds,
                                            thumbnailUrl: t.coverUrl,
                                            streamUrl: t.previewUrl
                                        )
                                        let allTracks = tracks.map { item in
                                            Track(
                                                id: "\(item.id)",
                                                title: item.title,
                                                artist: item.artistName,
                                                durationSeconds: item.durationSeconds,
                                                thumbnailUrl: item.coverUrl,
                                                streamUrl: item.previewUrl
                                            )
                                        }
                                        playerManager.play(track: selectedTrack, fromQueue: allTracks)
                                    }) {
                                        HStack(spacing: 12) {
                                            Text(String(format: "%02d", index + 1))
                                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                                .foregroundColor(.pukiTextSecondary)
                                                .frame(width: 24, alignment: .leading)
                                            
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(t.title)
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundColor(playerManager.currentTrack?.id == "\(t.id)" ? .pukiCoral : .white)
                                                    .lineLimit(1)
                                                
                                                Text(t.artistName)
                                                    .font(.system(size: 12))
                                                    .foregroundColor(.pukiTextSecondary)
                                                    .lineLimit(1)
                                            }
                                            
                                            Spacer()
                                            
                                            Text(formatDuration(t.durationSeconds))
                                                .font(.system(size: 12))
                                                .foregroundColor(.pukiTextSecondary)
                                            
                                            Image(systemName: playerManager.currentTrack?.id == "\(t.id)" && playerManager.isPlaying ? "waveform" : "play.fill")
                                                .foregroundColor(playerManager.currentTrack?.id == "\(t.id)" ? .pukiCoral : .pukiTextSecondary)
                                                .font(.system(size: 12))
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(playerManager.currentTrack?.id == "\(t.id)" ? Color.pukiCardElevated : Color.pukiCard.opacity(0.6))
                                        .cornerRadius(10)
                                        .padding(.horizontal, 20)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 140) // Memberikan ruang cukup agar lagu paling bawah tidak tertutup mini player
                }
            }
        }
        .task {
            let loaded = await DeezerService.shared.getAlbumTracks(albumId: album.id)
            await MainActor.run {
                self.tracks = loaded
                self.isLoading = false
            }
        }
    }
    
    private func playAllAlbumTracks() {
        guard let first = tracks.first else { return }
        let queue = tracks.map {
            Track(
                id: "\($0.id)",
                title: $0.title,
                artist: $0.artistName,
                durationSeconds: $0.durationSeconds,
                thumbnailUrl: $0.coverUrl,
                streamUrl: $0.previewUrl
            )
        }
        playerManager.play(track: queue[0], fromQueue: queue)
    }
    
    private func formatDuration(_ seconds: Int64) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Library Tab
struct LibraryTabView: View {
    @ObservedObject var store = LocalMusicStore.shared
    @EnvironmentObject var playerManager: AudioPlayerManager
    @State private var selectedSubTab: Int = 0 // 0: Playlist, 1: Favorit, 2: Offline
    @State private var showingCreatePlaylist = false
    @State private var newPlaylistName = ""
    @State private var activePlaylist: Playlist? = nil
    
    private let subTabs = ["Playlist", "Favorit", "Offline"]
    
    var body: some View {
        VStack(spacing: 16) {
            // Header Bar
            HStack {
                Text("Koleksi Musik")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                if selectedSubTab == 0 {
                    Button(action: { showingCreatePlaylist = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .bold))
                            Text("Playlist")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.pukiAmber)
                        .cornerRadius(16)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            // Sub-tabs Selector
            HStack(spacing: 8) {
                ForEach(0..<subTabs.count, id: \.self) { idx in
                    Button(action: { selectedSubTab = idx }) {
                        Text(subTabs[idx])
                            .font(.system(size: 13, weight: selectedSubTab == idx ? .bold : .medium))
                            .foregroundColor(selectedSubTab == idx ? .white : .pukiTextSecondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(selectedSubTab == idx ? Color.pukiCoral : Color.pukiCard)
                            .cornerRadius(20)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            
            // Tab Contents
            ScrollView {
                VStack(spacing: 16) {
                    if selectedSubTab == 0 {
                        // Section Playlists
                        if store.playlists.isEmpty {
                            emptyState(
                                icon: "music.note.list",
                                title: "Belum Ada Playlist",
                                subtitle: "Buat playlist pertama lu untuk mengelompokkan lagu favorit."
                            )
                        } else {
                            VStack(spacing: 10) {
                                ForEach(store.playlists) { pl in
                                    Button(action: { activePlaylist = pl }) {
                                        HStack(spacing: 14) {
                                            ZStack {
                                                Color.pukiCardElevated
                                                Image(systemName: "music.note.list")
                                                    .foregroundColor(.pukiCoral)
                                                    .font(.system(size: 22))
                                            }
                                            .frame(width: 56, height: 56)
                                            .cornerRadius(10)
                                            
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(pl.name)
                                                    .font(.system(size: 15, weight: .bold))
                                                    .foregroundColor(.white)
                                                Text("\(pl.tracks.count) Lagu")
                                                    .font(.system(size: 12))
                                                    .foregroundColor(.pukiTextSecondary)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .foregroundColor(.pukiTextSecondary)
                                                .font(.system(size: 13, weight: .semibold))
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(Color.pukiCard)
                                        .cornerRadius(12)
                                        .padding(.horizontal, 20)
                                    }
                                }
                            }
                        }
                    } else if selectedSubTab == 1 {
                        // Section Favorit
                        if store.favorites.isEmpty {
                            emptyState(
                                icon: "heart.slash",
                                title: "Belum Ada Lagu Favorit",
                                subtitle: "Ketuk tombol hati di pemutar musik untuk menambahkan lagu favorit."
                            )
                        } else {
                            VStack(spacing: 10) {
                                ForEach(store.favorites) { track in
                                    trackRow(track: track)
                                }
                            }
                        }
                    } else {
                        // Section Offline
                        emptyState(
                            icon: "arrow.down.circle",
                            title: "Musik Offline Siap Digunakan",
                            subtitle: "Unduh lagu untuk mendengarkan tanpa kuota data seluler."
                        )
                    }
                }
                .padding(.bottom, 140)
            }
        }
        .background(Color.pukiBackground)
        .alert("Buat Playlist Baru", isPresented: $showingCreatePlaylist) {
            TextField("Nama Playlist", text: $newPlaylistName)
            Button("Batal", role: .cancel) { newPlaylistName = "" }
            Button("Simpan") {
                store.createPlaylist(name: newPlaylistName)
                newPlaylistName = ""
            }
        }
        .sheet(item: $activePlaylist) { pl in
            PlaylistDetailSheetView(playlist: pl)
                .environmentObject(playerManager)
        }
    }
    
    private func trackRow(track: Track) -> some View {
        Button(action: {
            playerManager.play(track: track, fromQueue: store.favorites)
        }) {
            HStack(spacing: 12) {
                AsyncImage(url: URL(string: track.thumbnailUrl)) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Color.pukiCardElevated
                }
                .frame(width: 48, height: 48)
                .cornerRadius(8)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.system(size: 12))
                        .foregroundColor(.pukiTextSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "heart.fill")
                    .foregroundColor(.pukiCoral)
                    .font(.system(size: 14))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.pukiCard)
            .cornerRadius(10)
            .padding(.horizontal, 20)
        }
    }
    
    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundColor(.pukiCoral.opacity(0.8))
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundColor(.pukiTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(.top, 60)
    }
}

// MARK: - Playlist Detail Sheet View
struct PlaylistDetailSheetView: View {
    let playlist: Playlist
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var playerManager: AudioPlayerManager
    @ObservedObject var store = LocalMusicStore.shared
    
    var body: some View {
        ZStack {
            Color.pukiBackground.ignoresSafeArea()
            VStack(spacing: 16) {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.pukiTextSecondary)
                    }
                    Spacer()
                    Text(playlist.name.uppercased())
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.pukiAmber)
                    Spacer()
                    Button(action: {
                        store.deletePlaylist(id: playlist.id)
                        dismiss()
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 16))
                            .foregroundColor(.red)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                
                if playlist.tracks.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "music.note")
                            .font(.system(size: 40))
                            .foregroundColor(.pukiTextSecondary)
                        Text("Playlist ini masih kosong")
                            .font(.system(size: 14))
                            .foregroundColor(.pukiTextSecondary)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(Array(playlist.tracks.enumerated()), id: \.element.id) { idx, t in
                                Button(action: {
                                    playerManager.play(track: t, fromQueue: playlist.tracks)
                                }) {
                                    HStack(spacing: 12) {
                                        Text(String(format: "%02d", idx + 1))
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundColor(.pukiTextSecondary)
                                            .frame(width: 20)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(t.title)
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(.white)
                                                .lineLimit(1)
                                            Text(t.artist)
                                                .font(.system(size: 12))
                                                .foregroundColor(.pukiTextSecondary)
                                        }
                                        Spacer()
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 12))
                                            .foregroundColor(.pukiCoral)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(Color.pukiCard)
                                    .cornerRadius(10)
                                    .padding(.horizontal, 20)
                                }
                            }
                        }
                        .padding(.bottom, 60)
                    }
                }
            }
        }
    }
}

// MARK: - Settings Tab
struct SettingsTabView: View {
    @ObservedObject var store = LocalMusicStore.shared
    @State private var showingFilePicker = false
    @State private var showingExportSheet = false
    @State private var showingChangelog = false
    @State private var showingClearCacheAlert = false
    @State private var exportText: String = ""
    @State private var importMessage: String = ""
    @State private var showingAlert = false
    @State private var storageMB: Double = 0.0
    
    var body: some View {
        List {
            Section(header: Text("TENTANG APLIKASI").foregroundColor(.pukiTextSecondary)) {
                HStack {
                    Text("Versi Aplikasi")
                    Spacer()
                    Text("1.0.5 (iOS Native)")
                        .foregroundColor(.pukiCoral)
                }
                
                Button(action: { showingChangelog = true }) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundColor(.pukiAmber)
                        Text("Catatan Rilis (Changelog)")
                            .foregroundColor(.white)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.pukiTextSecondary)
                            .font(.system(size: 13))
                    }
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
                    Text("AVPlayer + InnerTube Direct CDN")
                        .foregroundColor(.pukiTextSecondary)
                }
            }
            .listRowBackground(Color.pukiCard)
            
            Section(header: Text("PENYIMPANAN & CACHE").foregroundColor(.pukiTextSecondary)) {
                HStack {
                    Text("Penggunaan Memori & Cache")
                    Spacer()
                    Text(String(format: "%.2f MB", storageMB))
                        .foregroundColor(.pukiAmber)
                        .fontWeight(.semibold)
                }
                
                Button(action: { showingClearCacheAlert = true }) {
                    HStack {
                        Image(systemName: "trash.fill")
                            .foregroundColor(.red)
                        Text("Bersihkan Cache Aplikasi")
                            .foregroundColor(.red)
                    }
                }
            }
            .listRowBackground(Color.pukiCard)
            
            Section(header: Text("PENGATURAN DOWNLOAD").foregroundColor(.pukiTextSecondary)) {
                Toggle(isOn: Binding(
                    get: { store.onlyWifiDownload },
                    set: { store.setOnlyWifiDownload($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Download Hanya Lewat Wi-Fi")
                            .foregroundColor(.white)
                            .font(.system(size: 15))
                        Text("Hemat kuota data seluler saat mengunduh lagu")
                            .foregroundColor(.pukiTextSecondary)
                            .font(.system(size: 12))
                    }
                }
                .tint(.pukiCoral)
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
        }
        .scrollContentBackground(.hidden)
        .background(Color.pukiBackground)
        .onAppear {
            storageMB = store.getStorageUsageMB()
        }
        .alert("Bersihkan Cache?", isPresented: $showingClearCacheAlert) {
            Button("Batal", role: .cancel) {}
            Button("Hapus", role: .destructive) {
                store.clearAllCaches()
                storageMB = store.getStorageUsageMB()
            }
        } message: {
            Text("File cache thumbnail dan buffer audio sementara akan dihapus untuk melegakan penyimpanan.")
        }
        .sheet(isPresented: $showingChangelog) {
            ChangelogSheetView()
        }
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


// MARK: - Changelog Sheet View
struct ChangelogSheetView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            Color.pukiBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundColor(.pukiAmber)
                        .font(.system(size: 18))
                    Text("CATATAN RILIS (CHANGELOG)")
                        .font(.system(size: 14, weight: .bold))
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
                .padding(.bottom, 12)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        // v1.0.5 Card
                        releaseCard(
                            version: "v1.0.5 (Build 5)",
                            date: "Oktober 2026",
                            badge: "TERBARU",
                            changes: [
                                "Background Audio & Lockscreen: Lagu tetap berputar saat keluar aplikasi, membuka notifikasi, atau layar terkunci.",
                                "Sinkronisasi Lirik Realtime: Lirik otomatis berjalan dan terpusat mengikuti ketukan musik.",
                                "Koleksi Musik Lengkap: Pembuatan playlist baru, kelola favorit, dan unduhan offline.",
                                "Perbaikan Tata Letak: Sheet album tidak lagi menutupi mini player dan bottom bar disempurnakan setara YouTube Music iOS.",
                                "Branding Resmi: Logo bulat Puki Music dengan teks gradient terpasang di header utama.",
                                "Manajemen Penyimpanan & Kuota: Indikator kapasitas cache lokal, tombol bersihkan cache, dan toggle download hanya via Wi-Fi."
                            ]
                        )
                        
                        // v1.0.4 Card
                        releaseCard(
                            version: "v1.0.4",
                            date: "Oktober 2026",
                            badge: "AUDIO ENGINE",
                            changes: [
                                "YouTube InnerTube Engine: Pemutaran lagu penuh (durasi 3-5 menit tanpa batas 30 detik).",
                                "Tampilan Album Vertikal: Daftar album pencarian mengalir rapi ke bawah 1:1 identik Android.",
                                "Diskografi & Sheet Album Interaktif: Ketuk album mana saja untuk memutar seluruh track."
                            ]
                        )
                        
                        // v1.0.3 Card
                        releaseCard(
                            version: "v1.0.3",
                            date: "Oktober 2026",
                            badge: "UI POLISH",
                            changes: [
                                "Full-screen edge-to-edge layout tanpa letterbox hitam di iPhone 12 Pro Max.",
                                "Ikon aplikasi resmi 1024x1024 Midnight Glow.",
                                "Navigasi frosted glass ultra-thin material."
                            ]
                        )
                    }
                    .padding(20)
                    .padding(.bottom, 40)
                }
            }
        }
    }
    
    private func releaseCard(version: String, date: String, badge: String, changes: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(version)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                Text(badge)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.pukiAmber)
                    .cornerRadius(4)
                Spacer()
                Text(date)
                    .font(.system(size: 12))
                    .foregroundColor(.pukiTextSecondary)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                ForEach(changes, id: \.self) { c in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .foregroundColor(.pukiCoral)
                            .font(.system(size: 14, weight: .bold))
                        Text(c)
                            .foregroundColor(Color(white: 0.88))
                            .font(.system(size: 13))
                            .lineSpacing(3)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.pukiCard)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Add To Playlist Modal Sheet
struct AddToPlaylistSheetView: View {
    let track: Track
    @ObservedObject var store = LocalMusicStore.shared
    @Environment(\.dismiss) var dismiss
    @State private var showingNewPlaylist = false
    @State private var newName = ""
    
    var body: some View {
        ZStack {
            Color.pukiBackground.ignoresSafeArea()
            VStack(spacing: 16) {
                HStack {
                    Text("TAMBAHKAN KE PLAYLIST")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.pukiCoral)
                        .tracking(1)
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.pukiTextSecondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                
                Button(action: { showingNewPlaylist = true }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.pukiAmber)
                        Text("Buat Playlist Baru")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(14)
                    .background(Color.pukiCard)
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
                }
                
                if store.playlists.isEmpty {
                    Spacer()
                    Text("Belum ada playlist yang dibuat.")
                        .foregroundColor(.pukiTextSecondary)
                        .font(.system(size: 14))
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(store.playlists) { pl in
                                let alreadyAdded = pl.tracks.contains(where: { $0.id == track.id })
                                Button(action: {
                                    if !alreadyAdded {
                                        store.addTrackToPlaylist(playlistId: pl.id, track: track)
                                    }
                                    dismiss()
                                }) {
                                    HStack {
                                        Image(systemName: "music.note.list")
                                            .foregroundColor(.pukiCoral)
                                        Text(pl.name)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(.white)
                                        Spacer()
                                        if alreadyAdded {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.pukiAmber)
                                                .font(.system(size: 14, weight: .bold))
                                        }
                                    }
                                    .padding(14)
                                    .background(Color.pukiCard)
                                    .cornerRadius(10)
                                    .padding(.horizontal, 20)
                                }
                            }
                        }
                    }
                }
            }
        }
        .alert("Playlist Baru", isPresented: $showingNewPlaylist) {
            TextField("Nama Playlist", text: $newName)
            Button("Batal", role: .cancel) { newName = "" }
            Button("Simpan") {
                store.createPlaylist(name: newName)
                if let last = store.playlists.last {
                    store.addTrackToPlaylist(playlistId: last.id, track: track)
                }
                newName = ""
                dismiss()
            }
        }
    }
}

// MARK: - Full Screen Player View
struct FullScreenPlayerView: View {
    let onLyricsTap: () -> Void
    @EnvironmentObject var playerManager: AudioPlayerManager
    @Environment(\.dismiss) var dismiss
    @ObservedObject var store = LocalMusicStore.shared
    @State private var showingAddToPlaylist = false
    @State private var showLyricsInline = false
    
    var body: some View {
        ZStack {
            Color.pukiBackground.ignoresSafeArea()
            
            if let track = playerManager.currentTrack {
                VStack(spacing: 20) {
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
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                showLyricsInline.toggle()
                            }
                        }) {
                            Image(systemName: showLyricsInline ? "music.note" : "quote.bubble.fill")
                                .font(.system(size: 20))
                                .foregroundColor(showLyricsInline ? .pukiAmber : .pukiCoral)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    
                    if showLyricsInline {
                        // In-Player Interactive Realtime Lyrics View
                        InlineLyricsPlayerView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Spacer()
                        
                        // Big Artwork
                        AsyncImage(url: URL(string: track.thumbnailUrl)) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Color.pukiCardElevated
                        }
                        .frame(width: 290, height: 290)
                        .cornerRadius(16)
                        .shadow(color: Color.pukiMagenta.opacity(0.35), radius: 24, x: 0, y: 12)
                        
                        Spacer()
                    }
                    
                    // Title, Artist, & Action Buttons (Favorite + Add to Playlist)
                    HStack(alignment: .center) {
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
                        
                        Spacer()
                        
                        // Add to Playlist Button
                        Button(action: { showingAddToPlaylist = true }) {
                            Image(systemName: "plus.rectangle.on.rectangle")
                                .font(.system(size: 20))
                                .foregroundColor(.pukiTextSecondary)
                        }
                        .padding(.trailing, 12)
                        
                        // Favorite Heart Button
                        Button(action: {
                            store.toggleFavorite(track: track)
                        }) {
                            Image(systemName: store.isFavorite(trackId: track.id) ? "heart.fill" : "heart")
                                .font(.system(size: 22))
                                .foregroundColor(store.isFavorite(trackId: track.id) ? .pukiCoral : .white)
                                .scaleEffect(store.isFavorite(trackId: track.id) ? 1.15 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: store.isFavorite(trackId: track.id))
                        }
                    }
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
        .sheet(isPresented: $showingAddToPlaylist) {
            if let tr = playerManager.currentTrack {
                AddToPlaylistSheetView(track: tr)
                    .presentationDetents([.medium, .large])
            }
        }
    }
    
    private func formatTime(_ sec: Double) -> String {
        let m = Int(sec) / 60
        let s = Int(sec) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Inline Lyrics Player View (Embedded inside Now Playing Screen)
struct InlineLyricsPlayerView: View {
    @EnvironmentObject var playerManager: AudioPlayerManager
    @State private var lyrics: LyricsResult?
    @State private var isLoading = true
    @State private var currentLineId: Int64? = nil
    
    var body: some View {
        VStack {
            if isLoading {
                Spacer()
                ProgressView().tint(.pukiCoral)
                Spacer()
            } else if let lrc = lyrics {
                if lrc.isSynced && !lrc.lines.isEmpty {
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 24) {
                                ForEach(lrc.lines) { line in
                                    let isCurrent = isLineActive(line, allLines: lrc.lines)
                                    Text(line.text)
                                        .font(.system(size: isCurrent ? 24 : 17, weight: isCurrent ? .bold : .medium))
                                        .foregroundColor(isCurrent ? .pukiAmber : .white.opacity(0.35))
                                        .multilineTextAlignment(.center)
                                        .scaleEffect(isCurrent ? 1.05 : 1.0)
                                        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isCurrent)
                                        .id(line.id)
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 30)
                        }
                        .onChange(of: playerManager.currentTime) { _ in
                            updateCurrentLine(lines: lrc.lines, proxy: proxy)
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
                            .padding(.vertical, 30)
                    }
                }
            } else {
                Spacer()
                Text("Lirik tidak tersedia")
                    .foregroundColor(.pukiTextSecondary)
                Spacer()
            }
        }
        .task {
            if let track = playerManager.currentTrack {
                self.lyrics = await LyricsService.shared.getLyrics(track: track)
                self.isLoading = false
            }
        }
    }
    
    private func updateCurrentLine(lines: [LyricLine], proxy: ScrollViewProxy) {
        let currentMs = Int64(playerManager.currentTime * 1000)
        guard let active = lines.last(where: { currentMs >= $0.timeMs }) else { return }
        if currentLineId != active.id {
            currentLineId = active.id
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(active.id, anchor: .center)
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

// MARK: - Lyrics Sheet View
struct LyricsSheetView: View {
    @EnvironmentObject var playerManager: AudioPlayerManager
    @Environment(\.dismiss) var dismiss
    @State private var lyrics: LyricsResult?
    @State private var isLoading = true
    @State private var currentLineId: Int64? = nil
    
    var body: some View {
        ZStack {
            Color.pukiBackground.ignoresSafeArea()
            
            VStack(spacing: 16) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lirik Lagu")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                        if let track = playerManager.currentTrack {
                            Text("\(track.title) • \(track.artist)")
                                .font(.system(size: 12))
                                .foregroundColor(.pukiTextSecondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.pukiTextSecondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                
                if isLoading {
                    Spacer()
                    ProgressView().tint(.pukiCoral)
                        .scaleEffect(1.3)
                    Spacer()
                } else if let lrc = lyrics {
                    if lrc.isSynced && !lrc.lines.isEmpty {
                        ScrollViewReader { proxy in
                            ScrollView(showsIndicators: false) {
                                VStack(spacing: 22) {
                                    ForEach(lrc.lines) { line in
                                        let isCurrent = isLineActive(line, allLines: lrc.lines)
                                        Text(line.text)
                                            .font(.system(size: isCurrent ? 24 : 17, weight: isCurrent ? .bold : .medium))
                                            .foregroundColor(isCurrent ? .pukiAmber : .pukiTextSecondary.opacity(0.45))
                                            .multilineTextAlignment(.center)
                                            .scaleEffect(isCurrent ? 1.05 : 1.0)
                                            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isCurrent)
                                            .id(line.id)
                                    }
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 40)
                            }
                            .onChange(of: playerManager.currentTime) { _ in
                                updateCurrentLine(lines: lrc.lines, proxy: proxy)
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
                    VStack(spacing: 12) {
                        Image(systemName: "quote.bubble")
                            .font(.system(size: 40))
                            .foregroundColor(.pukiTextSecondary.opacity(0.5))
                        Text("Lirik tidak tersedia untuk lagu ini.")
                            .font(.system(size: 14))
                            .foregroundColor(.pukiTextSecondary)
                    }
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
    
    private func updateCurrentLine(lines: [LyricLine], proxy: ScrollViewProxy) {
        let currentMs = Int64(playerManager.currentTime * 1000)
        guard let active = lines.last(where: { currentMs >= $0.timeMs }) else { return }
        if currentLineId != active.id {
            currentLineId = active.id
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(active.id, anchor: .center)
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
