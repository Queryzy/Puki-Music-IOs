import Foundation

class DownloadService: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = DownloadService()
    
    @Published var downloadedTrackIds: Set<String> = []
    @Published var downloadingTrackIds: Set<String> = []
    @Published var downloadProgress: [String: Double] = [:]
    
    private var backgroundSession: URLSession!
    private var taskToTrackId: [Int: String] = [:]
    private var trackMetaPending: [String: Track] = [:]
    
    private let offlineDirName = "offline_tracks"
    private let manifestFileName = "offline_manifest.json"
    
    override init() {
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: "com.puki.music.download.session")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        self.backgroundSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        
        ensureOfflineDirectoryExists()
        loadDownloadedTrackIds()
    }
    
    private func getOfflineDirectory() -> URL {
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
        
        DispatchQueue.main.async {
            self.downloadingTrackIds.insert(tid)
            self.downloadProgress[tid] = 0.05
        }
        
        Task {
            // 1. Resolve full stream URL via YouTube InnerTube
            if let streamUrlStr = await YouTubeStreamResolver.shared.resolveTrackStream(
                title: track.title,
                artist: track.artist,
                durationSeconds: track.durationSeconds
            ), let url = URL(string: streamUrlStr) {
                var req = URLRequest(url: url)
                req.setValue("com.google.android.youtube/21.03.36 (Linux; U; Android 14; Pixel 8 Pro) gzip", forHTTPHeaderField: "User-Agent")
                
                let task = self.backgroundSession.downloadTask(with: req)
                self.taskToTrackId[task.taskIdentifier] = tid
                self.trackMetaPending[tid] = track
                task.resume()
            } else {
                DispatchQueue.main.async {
                    self.downloadingTrackIds.remove(tid)
                    self.downloadProgress.removeValue(forKey: tid)
                }
            }
        }
    }
    
    func downloadBatch(tracks: [Track]) {
        for t in tracks {
            downloadTrack(track: t)
        }
    }
    
    func deleteDownloadedTrack(trackId: String) {
        if let file = getLocalAudioFileUrl(for: trackId) {
            try? FileManager.default.removeItem(at: file)
        }
        DispatchQueue.main.async {
            self.downloadedTrackIds.remove(trackId)
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
                self.saveManifest()
            }
        } catch {
            DispatchQueue.main.async {
                self.downloadingTrackIds.remove(tid)
                self.downloadProgress.removeValue(forKey: tid)
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let tid = taskToTrackId[task.taskIdentifier] else { return }
        taskToTrackId.removeValue(forKey: task.taskIdentifier)
        if error != nil {
            DispatchQueue.main.async {
                self.downloadingTrackIds.remove(tid)
                self.downloadProgress.removeValue(forKey: tid)
            }
        }
    }
    
    private func saveManifest() {
        let manifestFile = getOfflineDirectory().appendingPathComponent(manifestFileName)
        let array = Array(downloadedTrackIds)
        if let data = try? JSONSerialization.data(withJSONObject: array, options: .prettyPrinted) {
            try? data.write(to: manifestFile)
        }
    }
    
    private func loadDownloadedTrackIds() {
        let manifestFile = getOfflineDirectory().appendingPathComponent(manifestFileName)
        if let data = try? Data(contentsOf: manifestFile),
           let array = try? JSONSerialization.jsonObject(with: data) as? [String] {
            self.downloadedTrackIds = Set(array.filter { getLocalAudioFileUrl(for: $0) != nil })
        }
    }
}
