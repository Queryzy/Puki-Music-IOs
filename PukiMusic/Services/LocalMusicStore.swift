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
    var streamUrl: String? = nil
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
            var seen = Set<String>()
            var uniqueFavs: [Track] = []
            for f in favs {
                let norm = Track.normalizeId(f.id)
                if !seen.contains(norm) {
                    seen.insert(norm)
                    uniqueFavs.append(f)
                }
            }
            self.favorites = uniqueFavs
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
    
    func addRecentSearch(_ term: String, fromSync: Bool = false) {
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

        if !fromSync {
            SyncManager.shared.queueEvent(action: "ADD_SEARCH", data: ["query": trimmed])
        }
    }
    
    func clearRecentSearches() {
        self.recentSearches = []
        userDefaults.removeObject(forKey: keyRecentSearches)
    }
    
    func recordPlay(track: Track, fromSync: Bool = false) {
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
                streamUrl: track.streamUrl,
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

        if !fromSync {
            SyncManager.shared.queueEvent(action: "RECORD_PLAY", data: [
                "id": track.id,
                "title": track.title,
                "artist": track.artist,
                "duration": track.durationSeconds,
                "thumbnailUrl": track.thumbnailUrl,
                "playedAt": now
            ])
        }
    }
    
    func toggleFavorite(track: Track, fromSync: Bool = false) {
        var isNowFav = false
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        var updatedTrack = track
        updatedTrack.likedAt = now

        if let idx = favorites.firstIndex(where: { $0.id == track.id }) {
            favorites.remove(at: idx)
            isNowFav = false
        } else {
            favorites.insert(updatedTrack, at: 0)
            isNowFav = true
        }
        favorites.sort {
            if $0.likedAt != $1.likedAt {
                return $0.likedAt > $1.likedAt
            }
            return $0.title.lowercased() < $1.title.lowercased()
        }
        saveFavorites()

        if !fromSync {
            SyncManager.shared.queueEvent(action: "TOGGLE_FAVORITE", data: [
                "isLiked": isNowFav,
                "likedAt": now,
                "track": [
                    "id": track.id,
                    "title": track.title,
                    "artist": track.artist,
                    "duration": track.durationSeconds,
                    "thumbnailUrl": track.thumbnailUrl,
                    "likedAt": now
                ]
            ])
        }
    }

    func setFavoriteState(track: Track, isLiked: Bool, timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        let normId = Track.normalizeId(track.id)
        var effectiveTrack = track
        effectiveTrack.likedAt = track.likedAt > 0 ? track.likedAt : timestamp

        DispatchQueue.main.async {
            let existingIdx = self.favorites.firstIndex(where: { Track.normalizeId($0.id) == normId })
            if isLiked {
                if let idx = existingIdx {
                    self.favorites[idx] = effectiveTrack
                } else {
                    self.favorites.insert(effectiveTrack, at: 0)
                }
                self.favorites.sort {
                    if $0.likedAt != $1.likedAt {
                        return $0.likedAt > $1.likedAt
                    }
                    return $0.title.lowercased() < $1.title.lowercased()
                }
                self.saveFavorites()
            } else {
                if let idx = existingIdx {
                    self.favorites.remove(at: idx)
                    self.saveFavorites()
                }
            }
        }
    }
    
    func isFavorite(trackId: String) -> Bool {
        let norm = Track.normalizeId(trackId)
        return favorites.contains(where: { Track.normalizeId($0.id) == norm })
    }
    
    @discardableResult
    func createPlaylist(id: String = UUID().uuidString, name: String, fromSync: Bool = false) -> Playlist? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let existing = playlists.first(where: { $0.id == id || $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return existing
        }
        let newPl = Playlist(id: id, name: trimmed, tracks: [])
        playlists.append(newPl)
        savePlaylists()

        if !fromSync {
            SyncManager.shared.queueEvent(action: "UPDATE_PLAYLIST", data: [
                "playlistId": id,
                "name": trimmed,
                "operation": "CREATE"
            ])
        }
        return newPl
    }
    
    func deletePlaylist(id: String) {
        playlists.removeAll(where: { $0.id == id })
        savePlaylists()
    }
    
    // MARK: - Behavior Feed Engine (1:1 Android Parity)
    struct ArtistAffinity: Identifiable {
        var id: String { name }
        let name: String
        let playCount: Int
        let favoriteCount: Int
        let score: Int
        let avatarUrl: String
    }
    
    struct BehaviorFeedSection: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let query: String
        let reason: String
        var tracks: [Track] = []
    }
    
    func getUserTopArtists(limit: Int = 5) -> [ArtistAffinity] {
        var artistPlays: [String: Int] = [:]
        var artistThumbs: [String: String] = [:]
        
        for item in playHistory {
            let a = item.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            if !a.isEmpty && a.lowercased() != "unknown" {
                artistPlays[a, default: 0] += item.playCount
                if !item.thumbnailUrl.isEmpty && artistThumbs[a] == nil {
                    artistThumbs[a] = item.thumbnailUrl
                }
            }
        }
        
        var artistFavs: [String: Int] = [:]
        for f in favorites {
            let a = f.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            if !a.isEmpty && a.lowercased() != "unknown" {
                artistFavs[a, default: 0] += 1
                if !f.thumbnailUrl.isEmpty && artistThumbs[a] == nil {
                    artistThumbs[a] = f.thumbnailUrl
                }
            }
        }
        
        let allArtists = Set(artistPlays.keys).union(Set(artistFavs.keys))
        var list: [ArtistAffinity] = []
        for a in allArtists {
            let p = artistPlays[a] ?? 0
            let f = artistFavs[a] ?? 0
            let score = (p * 2) + (f * 5)
            if score > 0 {
                list.append(ArtistAffinity(
                    name: a,
                    playCount: p,
                    favoriteCount: f,
                    score: score,
                    avatarUrl: artistThumbs[a] ?? ""
                ))
            }
        }
        return list.sorted { $0.score > $1.score }.prefix(limit).map { $0 }
    }
    
    func getBehaviorFeedSections() -> [BehaviorFeedSection] {
        let topArtists = getUserTopArtists(limit: 5)
        var sections: [BehaviorFeedSection] = []
        
        let freqTracks = playHistory.filter { $0.playCount > 0 }
        let topSong1 = freqTracks.first
        let topSong2 = freqTracks.count > 1 ? freqTracks[1] : nil
        
        if let s1 = topSong1 {
            sections.append(BehaviorFeedSection(
                id: "song_affinity_1",
                title: "Mirip '\(s1.title)'",
                subtitle: "Lagu yang cocok dengan track yang paling sering kamu putar",
                query: "\(s1.artist) \(s1.title) mix audio",
                reason: "Berdasarkan '\(s1.title)' oleh \(s1.artist)"
            ))
            
            if let s2 = topSong2, s2.artist.caseInsensitiveCompare(s1.artist) != .orderedSame {
                sections.append(BehaviorFeedSection(
                    id: "song_affinity_2",
                    title: "Mirip '\(s2.title)'",
                    subtitle: "Rekomendasi track senada untuk seleramu",
                    query: "\(s2.artist) \(s2.title) mix songs",
                    reason: "Sering kamu putar belakangan ini"
                ))
            }
        }
        
        if !topArtists.isEmpty {
            let top1 = topArtists[0].name
            let top2 = topArtists.count > 1 ? topArtists[1].name : nil
            let mixDesc = top2 != nil ? "Kombinasi lagu dari \(top1) & \(top2!)" : "Koleksi lagu terbaik dari \(top1)"
            let mixQuery = top2 != nil ? "\(top1) \(top2!) mix audio" : "\(top1) best songs"
            
            sections.append(BehaviorFeedSection(
                id: "mix_personal",
                title: "Mix Selera Saya",
                subtitle: mixDesc,
                query: mixQuery,
                reason: top2 != nil ? "Berdasarkan \(top1) & \(top2!)" : "Berdasarkan \(top1)"
            ))
            
            sections.append(BehaviorFeedSection(
                id: "artist_top_1",
                title: "Spesial \(top1)",
                subtitle: "Lagu-lagu teratas dari artis favoritmu",
                query: "\(top1) top tracks audio",
                reason: "Paling sering kamu dengarkan (\(topArtists[0].playCount)x putar)"
            ))
            
            if let t2 = top2 {
                sections.append(BehaviorFeedSection(
                    id: "artist_top_2",
                    title: "Karena Kamu Suka \(t2)",
                    subtitle: "Trek pilihan dari \(t2)",
                    query: "\(t2) popular songs",
                    reason: "Artis favorit kedua kamu"
                ))
            }
        }
        return sections
    }
    
    func addTrackToPlaylist(playlistId: String, track: Track, fromSync: Bool = false) {
        if let idx = playlists.firstIndex(where: { $0.id == playlistId }) {
            if !playlists[idx].tracks.contains(where: { $0.id == track.id }) {
                playlists[idx].tracks.append(track)
                savePlaylists()

                if !fromSync {
                    SyncManager.shared.queueEvent(action: "UPDATE_PLAYLIST", data: [
                        "playlistId": playlistId,
                        "operation": "ADD_TRACK",
                        "track": [
                            "id": track.id,
                            "title": track.title,
                            "artist": track.artist,
                            "duration": track.durationSeconds,
                            "thumbnailUrl": track.thumbnailUrl
                        ]
                    ])
                }
            }
        }
    }

    func applyRemoteSyncEvent(action: String, data: [String: Any]) {
        switch action {
        case "RECORD_PLAY":
            if let id = data["id"] as? String,
               let title = data["title"] as? String,
               let artist = data["artist"] as? String {
                let duration = (data["duration"] as? NSNumber)?.int64Value ?? ((data["duration"] as? Int64) ?? 0)
                let thumb = (data["thumbnailUrl"] as? String) ?? ""
                let track = Track(id: id, title: title, artist: artist, durationSeconds: duration, thumbnailUrl: thumb)
                recordPlay(track: track, fromSync: true)
            }
        case "TOGGLE_FAVORITE":
            let isLiked = (data["isLiked"] as? Bool) ?? true
            let likedAt = (data["likedAt"] as? NSNumber)?.int64Value ?? ((data["likedAt"] as? Int64) ?? 0)
            if let trackDict = data["track"] as? [String: Any],
               let id = trackDict["id"] as? String,
               let title = trackDict["title"] as? String,
               let artist = trackDict["artist"] as? String {
                let duration = (trackDict["duration"] as? NSNumber)?.int64Value ?? ((trackDict["duration"] as? Int64) ?? 0)
                let thumb = (trackDict["thumbnailUrl"] as? String) ?? ""
                let trackLikedAt = (trackDict["likedAt"] as? NSNumber)?.int64Value ?? ((trackDict["likedAt"] as? Int64) ?? likedAt)
                let track = Track(id: id, title: title, artist: artist, durationSeconds: duration, thumbnailUrl: thumb, likedAt: trackLikedAt)
                setFavoriteState(track: track, isLiked: isLiked, timestamp: trackLikedAt > 0 ? trackLikedAt : Int64(Date().timeIntervalSince1970 * 1000))
            }
        case "ADD_SEARCH":
            if let query = data["query"] as? String, !query.isEmpty {
                addRecentSearch(query, fromSync: true)
            }
        case "UPDATE_PLAYLIST":
            if let playlistId = data["playlistId"] as? String {
                let op = (data["operation"] as? String) ?? ""
                if op == "CREATE", let name = data["name"] as? String {
                    createPlaylist(id: playlistId, name: name, fromSync: true)
                } else if op == "ADD_TRACK", let trackDict = data["track"] as? [String: Any],
                          let id = trackDict["id"] as? String,
                          let title = trackDict["title"] as? String,
                          let artist = trackDict["artist"] as? String {
                    let duration = (trackDict["duration"] as? NSNumber)?.int64Value ?? ((trackDict["duration"] as? Int64) ?? 0)
                    let thumb = (trackDict["thumbnailUrl"] as? String) ?? ""
                    let track = Track(id: id, title: title, artist: artist, durationSeconds: duration, thumbnailUrl: thumb)
                    addTrackToPlaylist(playlistId: playlistId, track: track, fromSync: true)
                }
            }
        default:
            break
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
        
        func sanitizeThumb(id: String, thumb: String) -> String {
            var t = thumb.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.hasPrefix("http://") || t.hasPrefix("https://") {
                if t.contains("ytimg.com"), let qIdx = t.firstIndex(of: "?") {
                    t = String(t[..<qIdx])
                }
                return t
            }
            // Jika thumb berisi path lokal Android (/data/...) atau kosong, buat URL publik resmi
            let cleanVid = Track.normalizeId(id)
            if !id.hasPrefix("dz_") && !cleanVid.isEmpty {
                return "https://i.ytimg.com/vi/\(cleanVid)/hqdefault.jpg"
            }
            return ""
        }
        
        // 1. Parse Favorites dari file Android
        if let favArr = json["favorites"] as? [[String: Any]] {
            for item in favArr {
                if let id = item["id"] as? String ?? (item["id"] as? Int64).map({ String($0) }),
                   let title = item["title"] as? String,
                   let artist = item["artist"] as? String {
                    let duration = item["duration"] as? Int64 ?? (item["duration"] as? Int).map({ Int64($0) }) ?? 0
                    let rawThumb = item["thumbnailUrl"] as? String ?? ""
                    let cleanThumb = sanitizeThumb(id: id, thumb: rawThumb)
                    let vCount = item["viewCount"] as? Int64 ?? 0
                    let lCount = item["likeCount"] as? Int64 ?? 0
                    
                    let track = Track(id: id, title: title, artist: artist, durationSeconds: duration, thumbnailUrl: cleanThumb, viewCount: vCount, likeCount: lCount)
                    if let idx = favorites.firstIndex(where: { $0.id == track.id }) {
                        favorites[idx] = track // Timpa dengan data baru
                    } else {
                        favorites.append(track)
                        importedFavs += 1
                    }
                }
            }
            saveFavorites()
        }
        
        // 2. Parse Playlists dari file Android (Update / Overwrite jika nama playlist sudah ada)
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
                            let rawThumb = t["thumbnailUrl"] as? String ?? ""
                            let cleanThumb = sanitizeThumb(id: id, thumb: rawThumb)
                            let vCount = t["viewCount"] as? Int64 ?? 0
                            let lCount = t["likeCount"] as? Int64 ?? 0
                            tracks.append(Track(id: id, title: title, artist: artist, durationSeconds: duration, thumbnailUrl: cleanThumb, viewCount: vCount, likeCount: lCount))
                        }
                    }
                }
                
                let playlist = Playlist(id: plId, name: plName, tracks: tracks)
                if let idx = playlists.firstIndex(where: { $0.name.caseInsensitiveCompare(playlist.name) == .orderedSame || $0.id == playlist.id }) {
                    // Update / Overwrite playlist yang sudah ada agar data lagu & cover langsung fresh
                    playlists[idx] = playlist
                    importedPls += 1
                } else {
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
