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
    
    func getLyrics(track: Track) async -> LyricsResult? {
        if let cached = cache[track.id] {
            return cached
        }
        
        let cleanTitle = clean(track.title)
        let cleanArtist = clean(track.artist)
        
        guard let encTitle = cleanTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encArtist = cleanArtist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        
        // 1. Direct GET
        let getURLString = "https://lrclib.net/api/get?artist_name=\(encArtist)&track_name=\(encTitle)&duration=\(track.durationSeconds)"
        if let url = URL(string: getURLString),
           let res = try? await fetchLrcResult(from: url) {
            cache[track.id] = res
            return res
        }
        
        // 2. Search fallback
        let searchURLString = "https://lrclib.net/api/search?q=\(encArtist)%20\(encTitle)"
        if let url = URL(string: searchURLString),
           let list = try? await fetchSearchList(from: url),
           let first = list.first {
            cache[track.id] = first
            return first
        }
        
        return nil
    }
    
    private func fetchLrcResult(from url: URL) async throws -> LyricsResult? {
        var req = URLRequest(url: url)
        req.setValue("PukiMusic/1.0", forHTTPHeaderField: "User-Agent")
        
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        
        return parseLrcJson(json)
    }
    
    private func fetchSearchList(from url: URL) async throws -> [LyricsResult] {
        var req = URLRequest(url: url)
        req.setValue("PukiMusic/1.0", forHTTPHeaderField: "User-Agent")
        
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        
        return arr.compactMap { parseLrcJson($0) }
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
        
        // Regex pattern: \[(\d{2}):(\d{2})\.(\d{2,3})\](.*)
        for raw in rawLines {
            guard let openBracket = raw.firstIndex(of: "["),
                  let closeBracket = raw.firstIndex(of: "]"),
                  openBracket < closeBracket else { continue }
            
            let timePart = String(raw[raw.index(after: openBracket)..<closeBracket])
            let lyricText = String(raw[raw.index(after: closeBracket)...]).trimmingCharacters(in: .whitespaces)
            
            let parts = timePart.split(separator: ":")
            if parts.count == 2,
               let min = Double(parts[0]) {
                let secParts = parts[1].split(separator: ".")
                if let sec = Double(secParts[0]) {
                    var ms = 0.0
                    if secParts.count > 1, let parsedMs = Double(secParts[1]) {
                        ms = secParts[1].count == 2 ? parsedMs * 10 : parsedMs
                    }
                    let totalMs = Int64((min * 60 + sec) * 1000 + ms)
                    lines.append(LyricLine(timeMs: totalMs, text: lyricText))
                }
            }
        }
        
        return lines.sorted { $0.timeMs < $1.timeMs }
    }
    
    private func clean(_ str: String) -> String {
        return str
            .replacingOccurrences(of: "(Official Music Video)", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "(Official Video)", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "(Official Audio)", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "[MV]", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
