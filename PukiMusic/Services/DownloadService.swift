import Foundation
import UIKit

class DownloadService: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = DownloadService()
    
    @Published var downloadedTrackIds: Set<String> = []
    @Published var downloadedTracks: [Track] = []
    @Published var downloadingTrackIds: Set<String> = []
    @Published var downloadProgress: [String: Double] = [:]
    
    private var downloadSession: URLSession!
    private var activeTasks: [String: URLSessionDownloadTask] = [:]
    private var taskToTrackId: [Int: String] = [:]
    private var trackMetaPending: [String: Track] = [:]
    private var backgroundTaskIds: [String: UIBackgroundTaskIdentifier] = [:]
    
    private let offlineDirName = "offline_tracks"
    private let manifestFileName = "offline_manifest.json"
    
    override init() {
        super.init()
        // URLSession dengan konfigurasi delegateQueue nil (background worker thread)
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = true
        self.downloadSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        
        ensureOfflineDirectoryExists()
        loadDownloadedTrackIds()
    }
    
    func getOfflineDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(offlineDirName, isDirectory: true)
    }
    
    private func ensureOfflineDirectoryExists() {
        let dir = getOfflineDirectory()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }
    }
    
    func getLocalAudioFileUrl(for trackId: String) -> URL? {
        let m4aFile = getOfflineDirectory().appendingPathComponent("\(trackId).m4a")
        if FileManager.default.fileExists(atPath: m4aFile.path),
           let attrs = try? FileManager.default.attributesOfItem(atPath: m4aFile.path),
           let size = attrs[.size] as? Int64, size > 150_000 {
            return m4aFile
        }
        let mp3File = getOfflineDirectory().appendingPathComponent("\(trackId).mp3")
        if FileManager.default.fileExists(atPath: mp3File.path),
           let attrs = try? FileManager.default.attributesOfItem(atPath: mp3File.path),
           let size = attrs[.size] as? Int64, size > 150_000 {
            return mp3File
        }
        return nil
    }
    
    func isTrackOffline(trackId: String) -> Bool {
        return downloadedTrackIds.contains(trackId) && getLocalAudioFileUrl(for: trackId) != nil
    }
    
    func downloadTrack(track: Track) {
        let tid = track.id
        guard !isTrackOffline(trackId: tid), !downloadingTrackIds.contains(tid) else { return }
        
        // Mulai iOS background task agar download tidak diputus saat user minimize aplikasi
        let bgTask = UIApplication.shared.beginBackgroundTask(withName: "PukiDownload_\(tid)") { [weak self] in
            self?.endBgTask(for: tid)
        }
        backgroundTaskIds[tid] = bgTask
        
        DispatchQueue.main.async {
            self.downloadingTrackIds.insert(tid)
            self.downloadProgress[tid] = 0.05
        }
        
        Task {
            // 1. Resolve full stream URL via YouTube InnerTube
            var streamUrlStr = await YouTubeStreamResolver.shared.resolveTrackStream(
                title: track.title,
                artist: track.artist,
                durationSeconds: track.durationSeconds
            )
            
            // 2. Resilient Fallback: Jika YouTube stream kosong atau gagal, gunakan stream direct audio Deezer yang 100% selalu tembus di iOS
            if streamUrlStr == nil {
                streamUrlStr = track.streamUrl
            }
            
            // 3. Jika track.streamUrl masih kosong, coba fetch track detail langsung dari Deezer API untuk preview mp3
            if streamUrlStr == nil, let dzId = Int64(track.id.replacingOccurrences(of: "dz_", with: "")),
               let dzUrl = URL(string: "https://api.deezer.com/track/\(dzId)") {
                if let (data, _) = try? await self.downloadSession.data(from: dzUrl),
                   let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                   let pUrl = json["preview"] as? String, !pUrl.isEmpty {
                    streamUrlStr = pUrl
                }
            }
            
            guard let validUrlStr = streamUrlStr, let url = URL(string: validUrlStr) else {
                DispatchQueue.main.async {
                    self.downloadingTrackIds.remove(tid)
                    self.downloadProgress.removeValue(forKey: tid)
                }
                self.endBgTask(for: tid)
                return
            }
            
            var req = URLRequest(url: url)
            req.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
            req.timeoutInterval = 60
            
            let task = self.downloadSession.downloadTask(with: req)
            self.taskToTrackId[task.taskIdentifier] = tid
            self.trackMetaPending[tid] = track
            self.activeTasks[tid] = task
            task.resume()
        }
    }
    
    private func endBgTask(for tid: String) {
        if let bgTask = backgroundTaskIds.removeValue(forKey: tid), bgTask != .invalid {
            UIApplication.shared.endBackgroundTask(bgTask)
        }
    }
    
    func downloadBatch(tracks: [Track]) {
        for t in tracks {
            downloadTrack(track: t)
        }
    }
    
    func deleteDownloadedTrack(trackId: String) {
        let m4aFile = getOfflineDirectory().appendingPathComponent("\(trackId).m4a")
        let mp3File = getOfflineDirectory().appendingPathComponent("\(trackId).mp3")
        try? FileManager.default.removeItem(at: m4aFile)
        try? FileManager.default.removeItem(at: mp3File)
        DispatchQueue.main.async {
            self.downloadedTrackIds.remove(trackId)
            self.downloadedTracks.removeAll(where: { $0.id == trackId })
            self.saveManifest()
        }
    }
    
    // MARK: - URLSessionDownloadDelegate
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let tid = taskToTrackId[downloadTask.taskIdentifier] else { return }
        
        let progress: Double
        if totalBytesExpectedToWrite > 0 {
            progress = min(0.99, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        } else {
            // Estimasi progres berbasis 3.5MB audio rata-rata
            let estimatedTotal: Double = 3_500_000.0
            progress = min(0.95, Double(totalBytesWritten) / estimatedTotal)
        }
        
        DispatchQueue.main.async {
            self.downloadProgress[tid] = progress
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let tid = taskToTrackId[downloadTask.taskIdentifier] else { return }
        
        // 1. Verifikasi HTTP Status Code dari Server
        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 && http.statusCode != 206 {
            print("Download task rejected with HTTP status: \(http.statusCode)")
            DispatchQueue.main.async {
                self.downloadingTrackIds.remove(tid)
                self.downloadProgress.removeValue(forKey: tid)
            }
            self.endBgTask(for: tid)
            return
        }
        
        // 2. Verifikasi Ukuran File Fisik (Minimal 150 KB untuk audio valid, bukan teks error HTML 2KB)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: location.path),
              let fileSize = attrs[.size] as? Int64, fileSize > 150_000 else {
            print("Download failed: downloaded file too small or invalid (< 150KB)")
            DispatchQueue.main.async {
                self.downloadingTrackIds.remove(tid)
                self.downloadProgress.removeValue(forKey: tid)
            }
            self.endBgTask(for: tid)
            return
        }
        
        // Tentukan ekstensi berdasarkan Content-Type / MIME
        let isMp3 = (downloadTask.response?.mimeType?.contains("audio/mpeg") == true) ||
                    (downloadTask.response?.mimeType?.contains("mp3") == true)
        let ext = isMp3 ? "mp3" : "m4a"
        let dest = getOfflineDirectory().appendingPathComponent("\(tid).\(ext)")
        
        // Bersihkan file lama jika ada sebelum replace
        try? FileManager.default.removeItem(at: dest)
        
        do {
            try FileManager.default.moveItem(at: location, to: dest)
            DispatchQueue.main.async {
                self.downloadedTrackIds.insert(tid)
                self.downloadingTrackIds.remove(tid)
                self.downloadProgress.removeValue(forKey: tid)
                if let meta = self.trackMetaPending.removeValue(forKey: tid) {
                    if !self.downloadedTracks.contains(where: { $0.id == tid }) {
                        self.downloadedTracks.append(meta)
                    }
                }
                self.saveManifest()
            }
        } catch {
            print("Failed to move downloaded file to \(dest.path): \(error)")
            DispatchQueue.main.async {
                self.downloadingTrackIds.remove(tid)
                self.downloadProgress.removeValue(forKey: tid)
            }
        }
        self.endBgTask(for: tid)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let tid = taskToTrackId[task.taskIdentifier] else { return }
        taskToTrackId.removeValue(forKey: task.taskIdentifier)
        activeTasks.removeValue(forKey: tid)
        if error != nil {
            DispatchQueue.main.async {
                self.downloadingTrackIds.remove(tid)
                self.downloadProgress.removeValue(forKey: tid)
            }
            self.endBgTask(for: tid)
        }
    }
    
    private func saveManifest() {
        let manifestFile = getOfflineDirectory().appendingPathComponent(manifestFileName)
        if let data = try? JSONEncoder().encode(downloadedTracks) {
            try? data.write(to: manifestFile)
        }
    }
    
    private func loadDownloadedTrackIds() {
        let manifestFile = getOfflineDirectory().appendingPathComponent(manifestFileName)
        if let data = try? Data(contentsOf: manifestFile),
           let tracks = try? JSONDecoder().decode([Track].self, from: data) {
            self.downloadedTracks = tracks.filter { getLocalAudioFileUrl(for: $0.id) != nil }
            self.downloadedTrackIds = Set(self.downloadedTracks.map { $0.id })
        }
    }
}
