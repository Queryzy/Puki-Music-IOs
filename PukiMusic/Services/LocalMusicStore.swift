import Foundation

struct Playlist: Identifiable, Codable {
    let id: String
    var name: String
    var tracks: [Track] = []
    var autoDownload: Bool = false
}

struct PlayHistoryItem: Identifiable, Codable {
    let id: String
    let title: String
    let artist: String
    let durationSeconds: Int64
    let thumbnailUrl: String
    var playCount: Int
    var lastPlayed: Int64
}

class LocalMusicStore: ObservableObject {
    static let shared = LocalMusicStore()
    private let userDefaults = UserDefaults.standard
    
    private let keyFavorites = "puki_favorites"
    private let keyPlaylists = "puki_playlists"
    private let keyPlayHistory = "puki_play_history"
    private let keyRecentSearches = "puki_recent_searches"
    
    @Published var favorites: [Track] = []
    @Published var playlists: [Playlist] = []
    @Published var recentSearches: [String] = []
    @Published var playHistory: [PlayHistoryItem] = []
    @Published var downloadedTrackIds: Set<String> = []
    @Published var onlyWifiDownload: Bool = true
    
    init() {
        loadData()
    }
    
    private func loadData() {
        if let favData = userDefaults.data(forKey: keyFavorites),
           let favs = try? JSONDecoder().decode([Track].self, from: favData) {
            self.favorites = favs
        }
        if let plData = userDefaults.data(forKey: keyPlaylists),
           let pls = try? JSONDecoder().decode([Playlist].self, from: plData) {
            self.playlists = pls
        }
        if let searches = userDefaults.stringArray(forKey: keyRecentSearches) {
            self.recentSearches = searches
        }
        if let histData = userDefaults.data(forKey: keyPlayHistory),
           let hist = try? JSONDecoder().decode([PlayHistoryItem].self, from: histData) {
            self.playHistory = hist
        }
        self.onlyWifiDownload = userDefaults.object(forKey: "puki_only_wifi") as? Bool ?? true
    }
    
    func saveFavorites() {
        if let data = try? JSONEncoder().encode(favorites) {
            userDefaults.set(data, forKey: keyFavorites)
        }
    }
    
    func savePlaylists() {
        if let data = try? JSONEncoder().encode(playlists) {
            userDefaults.set(data, forKey: keyPlaylists)
        }
    }
    
    func savePlayHistory() {
        if let data = try? JSONEncoder().encode(playHistory) {
            userDefaults.set(data, forKey: keyPlayHistory)
        }
    }
    
    func addRecentSearch(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var list = recentSearches
        list.removeAll(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame })
        list.insert(trimmed, at: 0)
        if list.count > 20 {
            list = Array(list.prefix(20))
        }
        self.recentSearches = list
        userDefaults.set(list, forKey: keyRecentSearches)
    }
    
    func clearRecentSearches() {
        self.recentSearches = []
        userDefaults.removeObject(forKey: keyRecentSearches)
    }
    
    func recordPlay(track: Track) {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        if let idx = playHistory.firstIndex(where: { $0.id == track.id }) {
            playHistory[idx].playCount += 1
            playHistory[idx].lastPlayed = now
        } else {
            let newItem = PlayHistoryItem(
                id: track.id,
                title: track.title,
                artist: track.artist,
                durationSeconds: track.durationSeconds,
                thumbnailUrl: track.thumbnailUrl,
                playCount: 1,
                lastPlayed: now
            )
            playHistory.insert(newItem, at: 0)
        }
        playHistory.sort {
            if $0.playCount != $1.playCount {
                return $0.playCount > $1.playCount
            }
            return $0.lastPlayed > $1.lastPlayed
        }
        if playHistory.count > 50 {
            playHistory = Array(playHistory.prefix(50))
        }
        savePlayHistory()
    }
    
    func toggleFavorite(track: Track) {
        if let idx = favorites.firstIndex(where: { $0.id == track.id }) {
            favorites.remove(at: idx)
        } else {
            favorites.append(track)
        }
        saveFavorites()
    }
    
    func isFavorite(trackId: String) -> Bool {
        favorites.contains(where: { $0.id == trackId })
    }
    
    func createPlaylist(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let newPl = Playlist(id: UUID().uuidString, name: trimmed, tracks: [])
        playlists.append(newPl)
        savePlaylists()
    }
    
    func deletePlaylist(id: String) {
        playlists.removeAll(where: { $0.id == id })
        savePlaylists()
    }
    
    func addTrackToPlaylist(playlistId: String, track: Track) {
        if let idx = playlists.firstIndex(where: { $0.id == playlistId }) {
            if !playlists[idx].tracks.contains(where: { $0.id == track.id }) {
                playlists[idx].tracks.append(track)
                savePlaylists()
            }
        }
    }
    
    func setOnlyWifiDownload(_ val: Bool) {
        self.onlyWifiDownload = val
        userDefaults.set(val, forKey: "puki_only_wifi")
    }
    
    // MARK: - Storage Management
    func getStorageUsageMB() -> Double {
        let fileManager = FileManager.default
        var totalBytes: Int64 = 0
        
        if let cacheUrl = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            totalBytes += folderSize(at: cacheUrl)
        }
        if let docUrl = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            totalBytes += folderSize(at: docUrl)
        }
        return Double(totalBytes) / (1024.0 * 1024.0)
    }
    
    private func folderSize(at url: URL) -> Int64 {
        let fileManager = FileManager.default
        guard let files = try? fileManager.subpathsOfDirectory(atPath: url.path) else { return 0 }
        var size: Int64 = 0
        for file in files {
            let path = url.appendingPathComponent(file).path
            if let attrs = try? fileManager.attributesOfItem(atPath: path),
               let fSize = attrs[.size] as? Int64 {
                size += fSize
            }
        }
        return size
    }
    
    func clearAllCaches() {
        let fileManager = FileManager.default
        if let cacheUrl = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            if let items = try? fileManager.contentsOfDirectory(at: cacheUrl, includingPropertiesForKeys: nil) {
                for item in items {
                    try? fileManager.removeItem(at: item)
                }
            }
        }
    }
    
    // MARK: - Export Data (1:1 Android Format Compatible)
    func exportBackupJson() -> String? {
        var root: [String: Any] = [
            "version": 1,
            "exportedAt": Int64(Date().timeIntervalSince1970 * 1000)
        ]
        
        // 1. Playlists
        let plArray: [[String: Any]] = playlists.map { pl in
            let trackList: [[String: Any]] = pl.tracks.map { t in
                [
                    "id": t.id,
                    "title": t.title,
                    "artist": t.artist,
                    "duration": t.durationSeconds,
                    "thumbnailUrl": t.thumbnailUrl,
                    "viewCount": t.viewCount,
                    "likeCount": t.likeCount
                ]
            }
            return [
                "id": pl.id,
                "name": pl.name,
                "autoDownload": pl.autoDownload,
                "tracks": trackList
            ]
        }
        root["playlists"] = plArray
        
        // 2. Favorites
        let favArray: [[String: Any]] = favorites.map { f in
            [
                "id": f.id,
                "title": f.title,
                "artist": f.artist,
                "duration": f.durationSeconds,
                "thumbnailUrl": f.thumbnailUrl,
                "viewCount": f.viewCount,
                "likeCount": f.likeCount
            ]
        }
        root["favorites"] = favArray
        root["recent_searches"] = recentSearches
        root["app_theme"] = "Midnight Glow"
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: root, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        return nil
    }
    
    // MARK: - Import Data (Bisa Baca File Export dari Android Langsung)
    func importBackupJson(_ jsonStr: String) -> (playlistsCount: Int, favoritesCount: Int) {
        guard let data = jsonStr.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return (0, 0)
        }
        
        var importedFavs = 0
        var importedPls = 0
        
        // 1. Parse Favorites dari file Android
        if let favArr = json["favorites"] as? [[String: Any]] {
            for item in favArr {
                if let id = item["id"] as? String ?? (item["id"] as? Int64).map({ String($0) }),
                   let title = item["title"] as? String,
                   let artist = item["artist"] as? String {
                    let duration = item["duration"] as? Int64 ?? (item["duration"] as? Int).map({ Int64($0) }) ?? 0
                    let thumb = item["thumbnailUrl"] as? String ?? ""
                    
                    let track = Track(id: id, title: title, artist: artist, durationSeconds: duration, thumbnailUrl: thumb)
                    if !favorites.contains(where: { $0.id == track.id }) {
                        favorites.append(track)
                        importedFavs += 1
                    }
                }
            }
            saveFavorites()
        }
        
        // 2. Parse Playlists dari file Android
        if let plArr = json["playlists"] as? [[String: Any]] {
            for plItem in plArr {
                let plId = plItem["id"] as? String ?? UUID().uuidString
                let plName = plItem["name"] as? String ?? "Playlist Impor"
                var tracks: [Track] = []
                
                if let trArr = plItem["tracks"] as? [[String: Any]] {
                    for t in trArr {
                        if let id = t["id"] as? String ?? (t["id"] as? Int64).map({ String($0) }),
                           let title = t["title"] as? String,
                           let artist = t["artist"] as? String {
                            let duration = t["duration"] as? Int64 ?? 0
                            let thumb = t["thumbnailUrl"] as? String ?? ""
                            tracks.append(Track(id: id, title: title, artist: artist, durationSeconds: duration, thumbnailUrl: thumb))
                        }
                    }
                }
                
                let playlist = Playlist(id: plId, name: plName, tracks: tracks)
                if !playlists.contains(where: { $0.name == playlist.name }) {
                    playlists.append(playlist)
                    importedPls += 1
                }
            }
            savePlaylists()
        }
        
        // 3. Parse Recent Searches (Riwayat Pencarian Android)
        if let sArr = json["recent_searches"] as? [String] {
            var mergedSearches = recentSearches
            for s in sArr {
                if !mergedSearches.contains(s) {
                    mergedSearches.append(s)
                }
            }
            self.recentSearches = mergedSearches
            userDefaults.set(mergedSearches, forKey: keyRecentSearches)
        }
        
        // 4. Parse Play History (Behavior / Lagu Sering Diputar Android)
        if let hArr = json["play_history"] as? [[String: Any]] {
            var currentMap: [String: PlayHistoryItem] = [:]
            for item in playHistory {
                currentMap[item.id] = item
            }
            for h in hArr {
                if let id = h["id"] as? String ?? (h["id"] as? Int64).map({ String($0) }),
                   let title = h["title"] as? String,
                   let artist = h["artist"] as? String {
                    let duration = h["duration"] as? Int64 ?? (h["duration"] as? Int).map({ Int64($0) }) ?? 0
                    let thumb = h["thumbnailUrl"] as? String ?? ""
                    let count = h["playCount"] as? Int ?? 1
                    let last = h["lastPlayed"] as? Int64 ?? 0
                    
                    if var existing = currentMap[id] {
                        existing.playCount += count
                        existing.lastPlayed = max(existing.lastPlayed, last)
                        currentMap[id] = existing
                    } else {
                        currentMap[id] = PlayHistoryItem(
                            id: id,
                            title: title,
                            artist: artist,
                            durationSeconds: duration,
                            thumbnailUrl: thumb,
                            playCount: count,
                            lastPlayed: last
                        )
                    }
                }
            }
            self.playHistory = currentMap.values.sorted {
                if $0.playCount != $1.playCount {
                    return $0.playCount > $1.playCount
                }
                return $0.lastPlayed > $1.lastPlayed
            }
            savePlayHistory()
        }
        
        return (importedPls, importedFavs)
    }
}
