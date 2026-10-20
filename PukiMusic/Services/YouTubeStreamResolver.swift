import Foundation

struct PipedStreamResponse: Codable {
    let audioStreams: [PipedAudioStream]?
}

struct PipedAudioStream: Codable {
    let url: String
    let format: String?
    let quality: String?
    let bitrate: Int?
    let mimeType: String?
}

class YouTubeStreamResolver {
    static let shared = YouTubeStreamResolver()
    private let session = URLSession.shared
    private var streamCache: [String: (url: String, timestamp: Date)] = [:]
    
    // Instance Piped publik yang stabil dan cepat
    private let pipedInstances = [
        "https://pipedapi.kavin.rocks",
        "https://api.piped.privacydev.net",
        "https://piped-api.lunar.icu"
    ]
    
    /// Resolve Deezer Track menjadi Audio Stream URL yang siap diputar di AVPlayer
    func resolveTrackStream(title: String, artist: String, durationSeconds: Int64) async -> String? {
        // 1. Cari video ID di YouTube Music via search query
        guard let videoId = await searchBestYouTubeVideoId(title: title, artist: artist, targetDuration: durationSeconds) else {
            return nil
        }
        
        // 2. Resolve direct CDN audio streaming URL
        return await resolveAudioCdnUrl(videoId: videoId)
    }
    
    /// Cari YouTube Video ID paling pas berdasarkan kesesuaian judul, artis, dan durasi
    private func searchBestYouTubeVideoId(title: String, artist: String, targetDuration: Int64) async -> String? {
        let cleanQuery = "\(artist) \(title) Audio"
        guard let encoded = cleanQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        
        for base in pipedInstances {
            guard let url = URL(string: "\(base)/search?q=\(encoded)&filter=music_songs") else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 6
            
            if let (data, resp) = try? await session.data(for: req),
               let http = resp as? HTTPURLResponse, http.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = json["items"] as? [[String: Any]] {
                
                for item in items {
                    if let urlStr = item["url"] as? String,
                       let duration = item["duration"] as? Int64 {
                        let diff = abs(duration - targetDuration)
                        if diff <= 8 { // Toleransi durasi maks 8 detik agar pas dengan versi lagu resmi
                            let videoId = urlStr.replacingOccurrences(of: "/watch?v=", with: "")
                            return videoId
                        }
                    }
                }
                
                // Fallback item pertama jika durasi beda tipis
                if let first = items.first, let urlStr = first["url"] as? String {
                    return urlStr.replacingOccurrences(of: "/watch?v=", with: "")
                }
            }
        }
        return nil
    }
    
    /// Ambil direct stream URL audio m4a/webm untuk AVPlayer
    func resolveAudioCdnUrl(videoId: String) async -> String? {
        if let cached = streamCache[videoId], Date().timeIntervalSince(cached.timestamp) < 3600 {
            return cached.url
        }
        
        for base in pipedInstances {
            guard let url = URL(string: "\(base)/streams/\(videoId)") else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 7
            
            if let (data, resp) = try? await session.data(for: req),
               let http = resp as? HTTPURLResponse, http.statusCode == 200,
               let streamData = try? JSONDecoder().decode(PipedStreamResponse.self, from: data),
               let audioList = streamData.audioStreams, !audioList.isEmpty {
                
                // Prioritaskan format m4a (AAC) karena paling native dan efisien baterai di iOS AVPlayer
                let bestStream = audioList.first(where: { ($0.format ?? "").lowercased().contains("m4a") }) ?? audioList.first
                if let audioUrl = bestStream?.url {
                    streamCache[videoId] = (url: audioUrl, timestamp: Date())
                    return audioUrl
                }
            }
        }
        return nil
    }
}
