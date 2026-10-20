import SwiftUI

@main
struct PukiMusicApp: App {
    @StateObject private var playerManager = AudioPlayerManager.shared
    
    var body: some Scene {
        WindowGroup {
            MainContainerView()
                .environmentObject(playerManager)
                .preferredColorScheme(.dark)
        }
    }
}

struct MainContainerView: View {
    @EnvironmentObject var playerManager: AudioPlayerManager
    @State private var selectedTab: Int = 0
    @State private var showFullScreenPlayer: Bool = false
    @State private var showLyricsSheet: Bool = false
    
    // In-line Navigation States (1:1 Android: Tidak menimpa mini player dan bottom menu bar)
    @State private var inlineActiveAlbum: DeezerAlbum? = nil
    @State private var inlineActivePlaylist: Playlist? = nil
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.pukiBackground.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Main Content with In-line Overlay
                ZStack {
                    TabView(selection: $selectedTab) {
                        HomeDashboardView()
                            .tag(0)
                        
                        SearchTabView()
                            .tag(1)
                        
                        LibraryTabView()
                            .tag(2)
                        
                        SettingsTabView()
                            .tag(3)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    
                    // In-line Album View (Di atas tab list, tetap di bawah mini player)
                    if let album = inlineActiveAlbum {
                        AlbumDetailSheetView(album: album, onDismiss: {
                            inlineActiveAlbum = nil
                        })
                        .transition(.move(edge: .trailing))
                        .zIndex(5)
                    }
                    
                    // In-line Playlist View (Di atas tab list, tetap di bawah mini player)
                    if let pl = inlineActivePlaylist {
                        PlaylistDetailSheetView(playlist: pl, onDismiss: {
                            inlineActivePlaylist = nil
                        })
                        .transition(.move(edge: .trailing))
                        .zIndex(6)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: inlineActiveAlbum?.id)
                .animation(.easeInOut(duration: 0.25), value: inlineActivePlaylist?.id)
                
                // Mini Player Bar
                if let track = playerManager.currentTrack {
                    MiniPlayerView(
                        track: track,
                        onTap: { showFullScreenPlayer = true },
                        onLyricsTap: { showLyricsSheet = true }
                    )
                }
                
                // Custom Bottom Nav Bar
                CustomBottomNavBar(selectedTab: $selectedTab, onTabSelected: { _ in
                    self.inlineActiveAlbum = nil
                    self.inlineActivePlaylist = nil
                })
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SearchArtist"))) { notif in
            if let artistName = notif.object as? String {
                self.inlineActiveAlbum = nil
                self.inlineActivePlaylist = nil
                self.selectedTab = 1 // Switch to Search Tab
                NotificationCenter.default.post(name: NSNotification.Name("ExecuteSearchQuery"), object: artistName)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenAlbumDetail"))) { notif in
            if let alb = notif.object as? DeezerAlbum {
                self.inlineActiveAlbum = alb
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenPlaylistDetail"))) { notif in
            if let pl = notif.object as? Playlist {
                self.inlineActivePlaylist = pl
            }
        }
        .sheet(isPresented: $showFullScreenPlayer) {
            FullScreenPlayerView(onLyricsTap: {
                showFullScreenPlayer = false
                showLyricsSheet = true
            })
            .environmentObject(playerManager)
        }
        .sheet(isPresented: $showLyricsSheet) {
            LyricsSheetView()
                .environmentObject(playerManager)
        }
    }
}

// MARK: - Custom Bottom Navigation Bar
struct CustomBottomNavBar: View {
    @Binding var selectedTab: Int
    var onTabSelected: ((Int) -> Void)? = nil
    
    var body: some View {
        HStack {
            navButton(icon: "house.fill", label: "Beranda", tab: 0)
            Spacer()
            navButton(icon: "magnifyingglass", label: "Cari", tab: 1)
            Spacer()
            navButton(icon: "square.stack.fill", label: "Koleksi", tab: 2)
            Spacer()
            navButton(icon: "gearshape.fill", label: "Pengaturan", tab: 3)
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(
            Color.pukiBackground.opacity(0.85)
                .background(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color.white.opacity(0.12)),
            alignment: .top
        )
    }
    
    private func navButton(icon: String, label: String, tab: Int) -> some View {
        Button(action: {
            selectedTab = tab
            onTabSelected?(tab)
        }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: selectedTab == tab ? .bold : .regular))
                    .foregroundColor(selectedTab == tab ? .pukiCoral : .pukiTextSecondary)
                
                Text(label)
                    .font(.system(size: 11, weight: selectedTab == tab ? .semibold : .medium))
                    .foregroundColor(selectedTab == tab ? .pukiCoral : .pukiTextSecondary)
            }
        }
    }
}

// MARK: - Mini Player
struct MiniPlayerView: View {
    let track: Track
    let onTap: () -> Void
    let onLyricsTap: () -> Void
    @EnvironmentObject var playerManager: AudioPlayerManager
    
    var progress: Double {
        guard playerManager.duration > 0 else { return 0 }
        return min(max(playerManager.currentTime / playerManager.duration, 0), 1)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // YouTube Music Seekbar Progress Line (Top of Miniplayer)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .foregroundColor(Color.white.opacity(0.15))
                        .frame(height: 2)
                    
                    Rectangle()
                        .foregroundColor(.pukiRedAccent)
                        .frame(width: geo.size.width * CGFloat(progress), height: 2)
                }
            }
            .frame(height: 2)
            
            HStack(spacing: 12) {
                // Artwork
                AsyncImage(url: URL(string: track.thumbnailUrl)) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Color.pukiCardElevated
                }
                .frame(width: 44, height: 44)
                .cornerRadius(6)
                
                // Track Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.pukiTextPrimary)
                        .lineLimit(1)
                    
                    Text(track.artist)
                        .font(.system(size: 12))
                        .foregroundColor(.pukiTextSecondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Lyrics Icon
                Button(action: onLyricsTap) {
                    Image(systemName: "quote.bubble")
                        .font(.system(size: 18))
                        .foregroundColor(.pukiTextSecondary)
                }
                
                // Play / Pause Button
                Button(action: { playerManager.togglePlayPause() }) {
                    ZStack {
                        if playerManager.isBuffering {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(width: 36, height: 36)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.pukiCard)
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
        }
    }
}
