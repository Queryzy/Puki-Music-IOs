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
        let file = getOfflineDirectory().appendingPathComponent("\(trackId).m4a")
        if FileManager.default.fileExists(atPath: file.path) {
            return file
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
            
            // Fallback ke preview URL jika resolver gagal
            if streamUrlStr == nil {
                streamUrlStr = track.streamUrl
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
            req.setValue("com.google.android.youtube/21.03.36 (Linux; U; Android 14; Pixel 8 Pro) gzip", forHTTPHeaderField: "User-Agent")
            
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
        let file = getOfflineDirectory().appendingPathComponent("\(trackId).m4a")
        try? FileManager.default.removeItem(at: file)
        DispatchQueue.main.async {
            self.downloadedTrackIds.remove(trackId)
            self.downloadedTracks.removeAll(where: { $0.id == trackId })
            self.saveManifest()
        }
    }
    
    // MARK: - URLSessionDownloadDelegate
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let tid = taskToTrackId[downloadTask.taskIdentifier] else { return }
        let progress = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0.5
        DispatchQueue.main.async {
            self.downloadProgress[tid] = progress
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let tid = taskToTrackId[downloadTask.taskIdentifier] else { return }
        let dest = getOfflineDirectory().appendingPathComponent("\(tid).m4a")
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
