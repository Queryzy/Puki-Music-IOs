import Foundation

struct LyricLine: Identifiable, Codable, Equatable {
    var id: Int64 { timeMs }
    let timeMs: Int64
    let text: String
}

struct LyricsResult: Codable {
    let isSynced: Bool
    let lines: [LyricLine]
    let plainLyrics: String?
}

class LyricsService {
    static let shared = LyricsService()
    private let session = URLSession.shared
    private var cache: [String: LyricsResult] = [:]
    
    private let userAgent = "PukiMusic/1.0 (https://github.com/nukeop/nuclear)"
    
    func getLyrics(track: Track) async -> LyricsResult? {
        if let cached = cache[track.id] {
            return cached
        }
        
        let cleanTitle = cleanSongTitle(track.title)
        let cleanArtist = cleanArtistName(track.artist)
        
        // 1. Direct GET dengan parameter durasi & artist/track bersih
        if let encTitle = cleanTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let encArtist = cleanArtist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            let getURLString = "https://lrclib.net/api/get?artist_name=\(encArtist)&track_name=\(encTitle)&duration=\(track.durationSeconds)"
            if let url = URL(string: getURLString),
               let res = try? await fetchLrcResult(from: url) {
                cache[track.id] = res
                return res
            }
        }
        
        // 2. Multi-query search bertingkat (1:1 Android LyricsService.kt)
        var searchQueries: [String] = []
        searchQueries.append("\(cleanArtist) \(cleanTitle)")
        searchQueries.append(cleanTitle)
        searchQueries.append("\(track.artist) \(track.title)")
        searchQueries.append(track.title)
        
        // Buat distinct
        var seen = Set<String>()
        let distinctQueries = searchQueries.filter { seen.insert($0).inserted }
        
        for q in distinctQueries {
            guard let encQ = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "https://lrclib.net/api/search?q=\(encQ)") else { continue }
            
            if let best = try? await fetchSearchList(from: url, trackDuration: track.durationSeconds),
               let validBest = best {
                cache[track.id] = validBest
                return validBest
            }
        }
        
        return nil
    }
    
    private func fetchLrcResult(from url: URL) async throws -> LyricsResult? {
        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 7
        
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        
        return parseLrcJson(json)
    }
    
    private func fetchSearchList(from url: URL, trackDuration: Int64) async throws -> LyricsResult? {
        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 7
        
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              !arr.isEmpty else {
            return nil
        }
        
        // Prioritas kandidat terbaik yang cocok dengan toleransi durasi (+-5 detik)
        var bestCandidate: [String: Any]? = nil
        var bestHasSync = false
        var bestDiff = Double.infinity
        
        for item in arr {
            let itemDur = item["duration"] as? Double ?? 0.0
            let synced = (item["syncedLyrics"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let plain = (item["plainLyrics"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if synced.isEmpty && plain.isEmpty { continue }
            
            let hasSync = !synced.isEmpty
            let diff = (trackDuration > 0 && itemDur > 0) ? abs(itemDur - Double(trackDuration)) : 0.0
            
            // Toleransi ketat <= 6 detik jika durasi diketahui
            if trackDuration > 0 && itemDur > 0 && diff > 6.0 {
                continue
            }
            
            if bestCandidate == nil {
                bestCandidate = item
                bestHasSync = hasSync
                bestDiff = diff
            } else if !bestHasSync && hasSync {
                bestCandidate = item
                bestHasSync = true
                bestDiff = diff
            } else if hasSync == bestHasSync && diff < bestDiff {
                bestCandidate = item
                bestDiff = diff
            }
        }
        
        guard let chosen = bestCandidate ?? arr.first else { return nil }
        return parseLrcJson(chosen)
    }
    
    private func parseLrcJson(_ json: [String: Any]) -> LyricsResult? {
        let synced = json["syncedLyrics"] as? String
        let plain = json["plainLyrics"] as? String
        
        if let synced = synced, !synced.isEmpty {
            let lines = parseLrc(synced)
            if !lines.isEmpty {
                return LyricsResult(isSynced: true, lines: lines, plainLyrics: plain)
            }
        }
        
        if let plain = plain, !plain.isEmpty {
            return LyricsResult(isSynced: false, lines: [], plainLyrics: plain)
        }
        
        return nil
    }
    
    func parseLrc(_ text: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        let rawLines = text.components(separatedBy: .newlines)
        
        // Regex pattern: \[(\d{2}):(\d{2}(?:\.\d+)?)\](.*)
        for raw in rawLines {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            
            guard let openBracket = trimmed.firstIndex(of: "["),
                  let closeBracket = trimmed.firstIndex(of: "]"),
                  openBracket < closeBracket else { continue }
            
            let timePart = String(trimmed[trimmed.index(after: openBracket)..<closeBracket])
            let lyricText = String(trimmed[trimmed.index(after: closeBracket)...]).trimmingCharacters(in: .whitespaces)
            
            let parts = timePart.split(separator: ":")
            if parts.count == 2,
               let min = Double(parts[0]) {
                let secStr = String(parts[1])
                if let secDouble = Double(secStr) {
                    let totalMs = Int64((min * 60.0 + secDouble) * 1000.0)
                    lines.append(LyricLine(timeMs: totalMs, text: lyricText))
                }
            }
        }
        
        return lines.sorted { $0.timeMs < $1.timeMs }
    }
    
    private func cleanSongTitle(_ title: String) -> String {
        var res = title
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
    
    private func cleanArtistName(_ artist: String) -> String {
        var res = artist
        let patterns = [
            "(?i)\\b(official|youtube|channel|music|video|vevo|records|entertainment)\\b",
            "(?i)\\s*-\\s*topic",
            "(?i)vevo"
        ]
        for p in patterns {
            res = res.replacingOccurrences(of: p, with: "", options: .regularExpression)
        }
        return res.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
