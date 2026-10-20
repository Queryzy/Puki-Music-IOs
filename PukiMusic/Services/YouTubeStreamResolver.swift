import Foundation

class YouTubeStreamResolver {
    static let shared = YouTubeStreamResolver()
    private let session = URLSession.shared
    private var streamCache: [String: (url: String, timestamp: Date)] = [:]
    private var videoIdCache: [String: String] = [:]
    
    init() {
        if let saved = UserDefaults.standard.dictionary(forKey: "puki_deezer_yt_map") as? [String: String] {
            self.videoIdCache = saved
        }
    }
    
    private func saveVideoIdCache(key: String, videoId: String) {
        videoIdCache[key] = videoId
        UserDefaults.standard.set(videoIdCache, forKey: "puki_deezer_yt_map")
    }
    
    /// Resolve Deezer Track menjadi Audio Stream URL durasi penuh yang siap diputar di AVPlayer / didownload
    func resolveTrackStream(title: String, artist: String, durationSeconds: Int64) async -> String? {
        let cacheKey = "\(artist.lowercased())__\(title.lowercased())"
        if let cachedId = videoIdCache[cacheKey], !cachedId.isEmpty {
            if let cdnUrl = await resolveAudioCdnUrl(videoId: cachedId) {
                return cdnUrl
            }
        }
        
        // 1. Cari video ID di YouTube Music via multi-query bertingkat (1:1 Android StreamResolver)
        guard let videoId = await searchBestYouTubeVideoId(title: title, artist: artist, durationSeconds: durationSeconds) else {
            return nil
        }
        
        saveVideoIdCache(key: cacheKey, videoId: videoId)
        
        // 2. Resolve direct CDN audio streaming URL via YouTube Android InnerTube
        return await resolveAudioCdnUrl(videoId: videoId)
    }
    
    /// Cari YouTube Video ID paling pas via YouTube Music InnerTube search bertingkat
    private func searchBestYouTubeVideoId(title: String, artist: String, durationSeconds: Int64) async -> String? {
        let cleanTitle = cleanStr(title)
        let cleanArtist = cleanStr(artist)
        
        // 4 variasi query pencarian bertingkat (1:1 Android)
        let queries = [
            "\(cleanArtist) - \(cleanTitle) Topic",
            "\(cleanArtist) \(cleanTitle) Official Audio",
            "\(cleanArtist) \(cleanTitle) Audio",
            "\(cleanArtist) \(cleanTitle)"
        ]
        
        guard let searchUrl = URL(string: "https://music.youtube.com/youtubei/v1/search?prettyPrint=false") else {
            return nil
        }
        
        for query in queries {
            var req = URLRequest(url: searchUrl)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
            req.timeoutInterval = 6
            
            let bodyJson: [String: Any] = [
                "context": [
                    "client": [
                        "clientName": "WEB_REMIX",
                        "clientVersion": "1.20231204.01.00",
                        "gl": "ID",
                        "hl": "id"
                    ]
                ],
                "query": query
            ]
            
            guard let httpBody = try? JSONSerialization.data(withJSONObject: bodyJson) else { continue }
            req.httpBody = httpBody
            
            do {
                let (data, resp) = try await session.data(for: req)
                guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
                      let text = String(data: data, encoding: .utf8) else {
                    continue
                }
                
                // Cari video ID pertama dari response
                let pattern = "\"videoId\":\"([a-zA-Z0-9_-]{11})\""
                if let regex = try? NSRegularExpression(pattern: pattern) {
                    let range = NSRange(text.startIndex..<text.endIndex, in: text)
                    let matches = regex.matches(in: text, range: range)
                    for m in matches {
                        if let r = Range(m.range(at: 1), in: text) {
                            let vid = String(text[r])
                            return vid
                        }
                    }
                }
            } catch {
                continue
            }
        }
        
        return nil
    }
    
    private func cleanStr(_ str: String) -> String {
        var res = str
        let patterns = [
            "(?i)\\b(official|music|video|audio|remastered|remaster|hd|4k|hq|visualizer|lyric video|lyrics|explicit|clean|original soundtrack|ost)\\b",
            "(?i)\\s*-\\s*(from|live|acoustic|instrumental|theme).*",
            "(?i)\\(.*?\\)",
            "(?i)\\[.*?\\]",
            "(?i)ft\\..*",
            "(?i)feat\\..*"
        ]
        for p in patterns {
            res = res.replacingOccurrences(of: p, with: "", options: .regularExpression)
        }
        return res.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Ambil direct stream URL audio m4a/mp4 durasi penuh langsung dari YouTube via Android InnerTube Client (itag 18)
    func resolveAudioCdnUrl(videoId: String) async -> String? {
        if let cached = streamCache[videoId], Date().timeIntervalSince(cached.timestamp) < 3600 {
            return cached.url
        }
        
        guard let playerUrl = URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false") else {
            return nil
        }
        
        var req = URLRequest(url: playerUrl)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("com.google.android.youtube/21.03.36 (Linux; U; Android 14; Pixel 8 Pro) gzip", forHTTPHeaderField: "User-Agent")
        req.setValue("3", forHTTPHeaderField: "X-YouTube-Client-Name")
        req.setValue("21.03.36", forHTTPHeaderField: "X-YouTube-Client-Version")
        req.timeoutInterval = 8
        
        let bodyJson: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "ANDROID",
                    "clientVersion": "21.03.36",
                    "androidSdkVersion": 34,
                    "hl": "en",
                    "gl": "US"
                ]
            ],
            "videoId": videoId,
            "contentCheckOk": true,
            "racyCheckOk": true
        ]
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: bodyJson) else { return nil }
        req.httpBody = httpBody
        
        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let streamingData = json["streamingData"] as? [String: Any] else {
                return nil
            }
            
            // 1. Cek formats (itag 18 adalah 360p muxed mp4 audio+video langsung tanpa cipher)
            if let formats = streamingData["formats"] as? [[String: Any]] {
                for f in formats {
                    if let itag = f["itag"] as? Int, itag == 18, let url = f["url"] as? String {
                        streamCache[videoId] = (url: url, timestamp: Date())
                        return url
                    }
                }
            }
            
            // 2. Cek adaptiveFormats audio jika ada direct url
            if let adaptive = streamingData["adaptiveFormats"] as? [[String: Any]] {
                for f in adaptive {
                    if let mime = f["mimeType"] as? String, mime.contains("audio"), let url = f["url"] as? String {
                        streamCache[videoId] = (url: url, timestamp: Date())
                        return url
                    }
                }
            }
        } catch {
            return nil
        }
        return nil
    }
}
