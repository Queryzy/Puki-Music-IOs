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
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.pukiBackground.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Tab Content
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
                
                // Mini Player Bar
                if let track = playerManager.currentTrack {
                    MiniPlayerView(
                        track: track,
                        onTap: { showFullScreenPlayer = true },
                        onLyricsTap: { showLyricsSheet = true }
                    )
                }
                
                // Custom Bottom Nav Bar
                CustomBottomNavBar(selectedTab: $selectedTab)
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
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(Color.pukiCard.ignoresSafeArea(edges: .bottom))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color.white.opacity(0.1)),
            alignment: .top
        )
    }
    
    private func navButton(icon: String, label: String, tab: Int) -> some View {
        Button(action: { selectedTab = tab }) {
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
                    Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
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
