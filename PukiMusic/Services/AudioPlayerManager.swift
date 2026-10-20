import Foundation
import AVFoundation
import MediaPlayer
import Combine

@MainActor
class AudioPlayerManager: ObservableObject {
    static let shared = AudioPlayerManager()
    
    @Published var currentTrack: Track?
    @Published var isPlaying: Bool = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var playlist: [Track] = []
    @Published var currentIndex: Int = 0
    @Published var isBuffering: Bool = false
    
    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var statusObserver: NSKeyValueObservation?
    
    init() {
        setupAudioSession()
        setupRemoteCommands()
    }
    
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
            try session.setActive(true)
        } catch {
            print("Failed to activate AVAudioSession: \(error)")
        }
        
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notif in
            guard let self = self,
                  let userInfo = notif.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
            
            if type == .ended {
                if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    if options.contains(.shouldResume) {
                        self.player?.play()
                        self.isPlaying = true
                        self.updateNowPlayingPlaybackInfo()
                    }
                }
            }
        }
    }
    
    func play(track: Track, fromQueue: [Track] = []) {
        if !fromQueue.isEmpty {
            self.playlist = fromQueue
            if let idx = fromQueue.firstIndex(where: { $0.id == track.id }) {
                self.currentIndex = idx
            }
        } else if !self.playlist.contains(where: { $0.id == track.id }) {
            self.playlist.append(track)
            self.currentIndex = self.playlist.count - 1
        }
        
        self.currentTrack = track
        self.isBuffering = true
        self.currentTime = 0
        self.duration = Double(track.durationSeconds)
        
        // Hentikan player lama agar tidak memutar potongan preview
        self.player?.pause()
        self.isPlaying = false
        
        // Resolve full YouTube stream langsung (tanpa double playback preview Deezer)
        Task {
            if let resolvedUrlStr = await YouTubeStreamResolver.shared.resolveTrackStream(
                title: track.title,
                artist: track.artist,
                durationSeconds: track.durationSeconds
            ), let resolvedUrl = URL(string: resolvedUrlStr) {
                var updatedTrack = track
                updatedTrack.streamUrl = resolvedUrlStr
                await MainActor.run {
                    self.currentTrack = updatedTrack
                    self.setupPlayer(url: resolvedUrl, track: updatedTrack)
                }
            } else if let fallbackPreview = track.streamUrl, let previewUrl = URL(string: fallbackPreview) {
                // Hanya fallback ke preview jika YouTube resolver benar-benar gagal
                await MainActor.run {
                    self.setupPlayer(url: previewUrl, track: track)
                }
            } else {
                await MainActor.run {
                    self.isBuffering = false
                    self.isPlaying = false
                }
            }
        }
    }

    
    private func setupPlayer(url: URL, track: Track) {
        removeTimeObserver()
        player?.pause()
        
        let playerItem = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: playerItem)
        newPlayer.automaticallyWaitsToMinimizeStalling = false
        player = newPlayer
        
        // Add periodic time observer (every 0.1s for buttery smooth lyrics sync)
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            self.currentTime = time.seconds
            self.updateNowPlayingPlaybackInfo()
        }
        
        // Observe status
        statusObserver = playerItem.observe(\.status, options: [.new, .old]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if item.status == .readyToPlay {
                    self.isBuffering = false
                    self.duration = item.duration.seconds.isFinite ? item.duration.seconds : Double(track.durationSeconds)
                    self.player?.play()
                    self.isPlaying = true
                    self.updateNowPlayingInfo(track: track)
                } else if item.status == .failed {
                    self.isBuffering = false
                    self.isPlaying = false
                }
            }
        }
        
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main) { [weak self] _ in
            self?.playNext()
        }
    }
    
    func togglePlayPause() {
        guard let player = player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
        updateNowPlayingPlaybackInfo()
    }
    
    func seek(to seconds: Double) {
        let targetTime = CMTime(seconds: seconds, preferredTimescale: 600)
        player?.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = seconds
        updateNowPlayingPlaybackInfo()
    }
    
    func playNext() {
        guard !playlist.isEmpty else { return }
        currentIndex = (currentIndex + 1) % playlist.count
        let nextTrack = playlist[currentIndex]
        play(track: nextTrack, fromQueue: playlist)
    }
    
    func playPrevious() {
        guard !playlist.isEmpty else { return }
        currentIndex = (currentIndex - 1 + playlist.count) % playlist.count
        let prevTrack = playlist[currentIndex]
        play(track: prevTrack, fromQueue: playlist)
    }
    
    private func removeTimeObserver() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        statusObserver?.invalidate()
        statusObserver = nil
    }
    
    // MARK: - Lockscreen & Control Center Integration
    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.playNext()
            return .success
        }
        
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.playPrevious()
            return .success
        }
        
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let event = event as? MPChangePlaybackPositionCommandEvent {
                self?.seek(to: event.positionTime)
                return .success
            }
            return .commandFailed
        }
    }
    
    private func updateNowPlayingInfo(track: Track) {
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = track.title
        nowPlayingInfo[MPMediaItemPropertyArtist] = track.artist
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        
        // Artwork async load
        if let artUrl = URL(string: track.thumbnailUrl) {
            Task {
                if let (data, _) = try? await URLSession.shared.data(from: artUrl),
                   let image = UIImage(data: data) {
                    let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    var currentInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                    currentInfo[MPMediaItemPropertyArtwork] = artwork
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = currentInfo
                }
            }
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    private func updateNowPlayingPlaybackInfo() {
        guard var currentInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        currentInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        currentInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = currentInfo
    }
}
