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
        var videoId = await searchBestYouTubeVideoId(title: title, artist: artist, durationSeconds: durationSeconds)
        
        // Coba resolve CDN dari videoId hasil search bertingkat
        if let vid = videoId, let cdnUrl = await resolveAudioCdnUrl(videoId: vid) {
            saveVideoIdCache(key: cacheKey, videoId: vid)
            return cdnUrl
        }
        
        // 1b. Fallback: Jika search YouTube Music gagal atau cipher terblokir, cari alternatif via direct YouTube search (Official Audio / Topic)
        let fallbackQueries = [
            "\(cleanStr(artist)) \(cleanStr(title)) Topic",
            "\(cleanStr(artist)) \(cleanStr(title)) Audio",
            "\(cleanStr(artist)) \(cleanStr(title))"
        ]
        
        for q in fallbackQueries {
            let ytTracks = await searchYouTubeTracks(query: q)
            for track in ytTracks {
                if let cdn = await resolveAudioCdnUrl(videoId: track.id) {
                    saveVideoIdCache(key: cacheKey, videoId: track.id)
                    return cdn
                }
            }
        }
        
        return nil
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
    
    /// Search YouTube langsung untuk track lokal/Indonesia (Noah, Peterpan, dll) - 1:1 Android
    func searchYouTubeTracks(query: String) async -> [Track] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.youtube.com/results?search_query=\(encoded)&sp=EgIQAQ%253D%253D") else {
            return []
        }
        
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        req.setValue("id-ID,id;q=0.9,en-US;q=0.8,en;q=0.7", forHTTPHeaderField: "Accept-Language")
        req.timeoutInterval = 8
        
        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let html = String(data: data, encoding: .utf8) else {
                return []
            }
            
            // Ekstrak ytInitialData JSON
            let pattern = "var ytInitialData = (\\{.*?\\});</script>"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html)),
                  let r = Range(match.range(at: 1), in: html),
                  let json = try? JSONSerialization.jsonObject(with: Data(html[r].utf8)) as? [String: Any] else {
                return []
            }
            
            let contents = (((json["contents"] as? [String: Any])?["twoColumnSearchResultsRenderer"] as? [String: Any])?["primaryContents"] as? [String: Any])?["sectionListRenderer"] as? [String: Any]
            guard let sectionList = contents?["contents"] as? [[String: Any]] else { return [] }
            
            var tracks: [Track] = []
            for sec in sectionList {
                guard let itemSec = (sec["itemSectionRenderer"] as? [String: Any])?["contents"] as? [[String: Any]] else { continue }
                for it in itemSec {
                    guard let vr = it["videoRenderer"] as? [String: Any],
                          let videoId = vr["videoId"] as? String else { continue }
                    
                    let titleRuns = (vr["title"] as? [String: Any])?["runs"] as? [[String: Any]] ?? []
                    let title = titleRuns.compactMap { $0["text"] as? String }.joined()
                    
                    let ownerRuns = (vr["ownerText"] as? [String: Any])?["runs"] as? [[String: Any]] ?? []
                    let artist = ownerRuns.compactMap { $0["text"] as? String }.joined().replacingOccurrences(of: " - Topic", with: "").trimmingCharacters(in: .whitespaces)
                    
                    let lengthText = (vr["lengthText"] as? [String: Any])?["simpleText"] as? String ?? ""
                    let parts = lengthText.split(separator: ":").compactMap { Int64($0) }
                    var durationSec: Int64 = 0
                    if parts.count == 2 {
                        durationSec = parts[0] * 60 + parts[1]
                    } else if parts.count == 3 {
                        durationSec = parts[0] * 3600 + parts[1] * 60 + parts[2]
                    }
                    
                    let thumbUrl = "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg"
                    let viewCountText = (vr["viewCountText"] as? [String: Any])?["simpleText"] as? String ?? ""
                    var viewCount: Int64 = 0
                    if let rawNum = viewCountText.components(separatedBy: CharacterSet.decimalDigits.inverted).joined().nonEmpty,
                       let num = Int64(rawNum) {
                        viewCount = num
                    }
                    
                    tracks.append(Track(
                        id: videoId,
                        title: title,
                        artist: artist.isEmpty ? "YouTube Music" : artist,
                        durationSeconds: durationSec,
                        thumbnailUrl: thumbUrl,
                        streamUrl: nil,
                        viewCount: viewCount,
                        likeCount: 0
                    ))
                    
                    if tracks.count >= 25 { break }
                }
                if tracks.count >= 25 { break }
            }
            return tracks
        } catch {
            return []
        }
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
    
    /// Ambil direct stream URL pure audio m4a/opus langsung dari YouTube via ANDROID_VR InnerTube (itag 140 / 139 / 251)
    func resolveAudioCdnUrl(videoId: String) async -> String? {
        if let cached = streamCache[videoId], Date().timeIntervalSince(cached.timestamp) < 3600 {
            return cached.url
        }
        
        guard let playerUrl = URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false") else {
            return nil
        }
        
        // 1. Coba ANDROID_VR Client untuk mendapatkan pure audio adaptive streams (itag 140 m4a / 251 webm)
        let vrBody: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "ANDROID_VR",
                    "clientVersion": "1.60.19",
                    "hl": "en",
                    "gl": "US"
                ]
            ],
            "videoId": videoId,
            "contentCheckOk": true,
            "racyCheckOk": true
        ]
        
        if let directAudioUrl = await fetchDirectStream(url: playerUrl, body: vrBody, isPureAudioPreferred: true) {
            streamCache[videoId] = (url: directAudioUrl, timestamp: Date())
            return directAudioUrl
        }
        
        // 2. Fallback ke ANDROID client standard (itag 18) jika VR client gagal
        let androidBody: [String: Any] = [
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
        
        if let fallbackUrl = await fetchDirectStream(url: playerUrl, body: androidBody, isPureAudioPreferred: false) {
            streamCache[videoId] = (url: fallbackUrl, timestamp: Date())
            return fallbackUrl
        }
        
        return nil
    }
    
    private func fetchDirectStream(url: URL, body: [String: Any], isPureAudioPreferred: Bool) async -> String? {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 8
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        req.httpBody = httpBody
        
        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let streamingData = json["streamingData"] as? [String: Any] else {
                return nil
            }
            
            // Prioritas 1: Pure audio m4a (itag 140 / 139) - 100% native supported by AVPlayer tanpa video container
            if let adaptive = streamingData["adaptiveFormats"] as? [[String: Any]] {
                // Cari m4a itag 140 dulu (128kbps AAC)
                for f in adaptive {
                    if let itag = f["itag"] as? Int, itag == 140, let streamUrl = f["url"] as? String {
                        return streamUrl
                    }
                }
                // Cari any audio/mp4 m4a
                for f in adaptive {
                    if let mime = f["mimeType"] as? String, mime.contains("audio/mp4"), let streamUrl = f["url"] as? String {
                        return streamUrl
                    }
                }
            }
            
            // Prioritas 2: itag 18 (muxed 360p mp4)
            if let formats = streamingData["formats"] as? [[String: Any]] {
                for f in formats {
                    if let itag = f["itag"] as? Int, itag == 18, let streamUrl = f["url"] as? String {
                        return streamUrl
                    }
                }
            }
        } catch {
            return nil
        }
        return nil
    }
}

private extension String {
    var nonEmpty: String? {
        return self.isEmpty ? nil : self
    }
}
