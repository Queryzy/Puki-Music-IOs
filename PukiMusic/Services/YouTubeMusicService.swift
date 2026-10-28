import Foundation

/// Service pemanggil YouTube Music InnerTube WEB_REMIX resmi (1:1 Android YouTubeMusicRepository)
final class YouTubeMusicService {
    static let shared = YouTubeMusicService()
    private init() {}
    
    private let baseURL = "https://music.youtube.com/youtubei/v1"
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        return URLSession(configuration: config)
    }()
    
    private func createBaseContext() -> [String: Any] {
        return [
            "client": [
                "clientName": "WEB_REMIX",
                "clientVersion": "1.20240401.01.00",
                "hl": "id",
                "gl": "ID"
            ]
        ]
    }
    
    private func postInnerTube(endpoint: String, payload: [String: Any]) async throws -> [String: Any] {
        guard let url = URL(string: "\(baseURL)/\(endpoint)?prettyPrint=false") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.youtube.com/", forHTTPHeaderField: "Referer")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        return json
    }
    
    /// Cari Album resmi YouTube Music (Filter: params 'EgWKAQIYAWoMEAMQBBAJEA4QChAF')
    func searchAlbums(query: String, limit: Int = 20) async -> [Album] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        
        let payload: [String: Any] = [
            "context": createBaseContext(),
            "query": q,
            "params": "EgWKAQIYAWoMEAMQBBAJEA4QChAF"
        ]
        
        do {
            let json = try await postInnerTube(endpoint: "search", payload: payload)
            guard let contentsObj = json["contents"] as? [String: Any],
                  let tabbed = contentsObj["tabbedSearchResultsRenderer"] as? [String: Any],
                  let tabs = tabbed["tabs"] as? [[String: Any]],
                  let firstTab = tabs.first,
                  let tabRend = firstTab["tabRenderer"] as? [String: Any],
                  let content = tabRend["content"] as? [String: Any],
                  let secList = content["sectionListRenderer"] as? [String: Any],
                  let secContents = secList["contents"] as? [[String: Any]] else {
                return []
            }
            
            var albums: [Album] = []
            for sec in secContents {
                guard let shelf = sec["musicShelfRenderer"] as? [String: Any],
                      let items = shelf["contents"] as? [[String: Any]] else {
                    continue
                }
                
                for item in items {
                    if albums.count >= limit { break }
                    guard let flex = item["musicResponsiveListItemRenderer"] as? [String: Any],
                          let nav = flex["navigationEndpoint"] as? [String: Any],
                          let browseEndpoint = nav["browseEndpoint"] as? [String: Any],
                          let browseId = browseEndpoint["browseId"] as? String,
                          !browseId.isEmpty else {
                        continue
                    }
                    
                    guard let flexCols = flex["flexColumns"] as? [[String: Any]], flexCols.count >= 2 else {
                        continue
                    }
                    
                    // Col 0: Title
                    let col0 = flexCols[0]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any]
                    let col0Text = col0?["text"] as? [String: Any]
                    let col0Runs = col0Text?["runs"] as? [[String: Any]]
                    let title = col0Runs?.first?["text"] as? String ?? ""
                    guard !title.isEmpty else { continue }
                    
                    // Col 1: Record Type • Artist • Year
                    let col1 = flexCols[1]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any]
                    let col1Text = col1?["text"] as? [String: Any]
                    let col1Runs = col1Text?["runs"] as? [[String: Any]]
                    
                    var recordType = ""
                    var artistName = ""
                    if let runs = col1Runs {
                        if let firstRun = runs.first?["text"] as? String {
                            recordType = firstRun.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                        for run in runs {
                            if let runNav = run["navigationEndpoint"] as? [String: Any],
                               let rBrowse = runNav["browseEndpoint"] as? [String: Any],
                               let configs = rBrowse["browseEndpointContextSupportedConfigs"] as? [String: Any],
                               let mConfig = configs["browseEndpointContextMusicConfig"] as? [String: Any],
                               let pageType = mConfig["pageType"] as? String,
                               pageType == "MUSIC_PAGE_TYPE_ARTIST" {
                                artistName = run["text"] as? String ?? ""
                                break
                            }
                        }
                        if artistName.isEmpty && runs.count >= 3 {
                            artistName = runs[2]["text"] as? String ?? ""
                        }
                    }
                    if artistName.isEmpty { artistName = q }
                    
                    // Strict Album Filter: Drop single / buku audio / podcast (only allow Album or EP)
                    if recordType.contains("single") || recordType.contains("buku audio") || recordType.contains("audiobook") {
                        continue
                    }
                    
                    // Thumbnail
                    let thumbObj = flex["thumbnail"] as? [String: Any]
                    let mThumb = thumbObj?["musicThumbnailRenderer"] as? [String: Any]
                    let tObj = mThumb?["thumbnail"] as? [String: Any]
                    let thumbs = tObj?["thumbnails"] as? [[String: Any]]
                    var thumbUrl = thumbs?.last?["url"] as? String ?? ""
                    
                    // Upscale Google/YTM thumbnail to crisp 544x544
                    if thumbUrl.contains("=w") && thumbUrl.contains("-h") {
                        if let match = thumbUrl.range(of: "=w\\d+-h\\d+.*", options: .regularExpression) {
                            thumbUrl.replaceSubrange(match, with: "=w544-h544-l90-rj")
                        }
                    }
                    
                    albums.append(
                        Album(
                            id: browseId,
                            title: title,
                            artist: artistName,
                            trackCount: 0,
                            thumbnailUrl: thumbUrl,
                            url: browseId
                        )
                    )
                }
            }
            return albums
        } catch {
            return []
        }
    }
    
    /// Ambil daftar lagu album via browseId (MPREb_...)
    func getAlbumTracks(browseId: String) async -> [Track] {
        let payload: [String: Any] = [
            "context": createBaseContext(),
            "browseId": browseId
        ]
        
        do {
            let json = try await postInnerTube(endpoint: "browse", payload: payload)
            guard let contentsObj = json["contents"] as? [String: Any],
                  let twoCol = contentsObj["twoColumnBrowseResultsRenderer"] as? [String: Any] else {
                return []
            }
            
            // Extract album cover from header
            var albumCover = ""
            var defaultArtist = ""
            if let tabs = twoCol["tabs"] as? [[String: Any]],
               let tab0 = tabs.first?["tabRenderer"] as? [String: Any],
               let content = tab0["content"] as? [String: Any],
               let secList = content["sectionListRenderer"] as? [String: Any],
               let secContents = secList["contents"] as? [[String: Any]],
               let header = secContents.first?["musicResponsiveHeaderRenderer"] as? [String: Any] {
                
                let thumbObj = header["thumbnail"] as? [String: Any]
                let mThumb = thumbObj?["musicThumbnailRenderer"] as? [String: Any]
                let tObj = mThumb?["thumbnail"] as? [String: Any]
                let thumbs = tObj?["thumbnails"] as? [[String: Any]]
                albumCover = thumbs?.last?["url"] as? String ?? ""
                
                if let subObj = header["subtitle"] as? [String: Any],
                   let subRuns = subObj["runs"] as? [[String: Any]] {
                    for run in subRuns {
                        if let rNav = run["navigationEndpoint"] as? [String: Any],
                           let rBrowse = rNav["browseEndpoint"] as? [String: Any],
                           let configs = rBrowse["browseEndpointContextSupportedConfigs"] as? [String: Any],
                           let mConfig = configs["browseEndpointContextMusicConfig"] as? [String: Any],
                           let pageType = mConfig["pageType"] as? String,
                           pageType == "MUSIC_PAGE_TYPE_ARTIST" {
                            defaultArtist = run["text"] as? String ?? ""
                            break
                        }
                    }
                }
            }
            
            if albumCover.contains("=w") && albumCover.contains("-h") {
                if let match = albumCover.range(of: "=w\\d+-h\\d+.*", options: .regularExpression) {
                    albumCover.replaceSubrange(match, with: "=w544-h544-l90-rj")
                }
            }
            
            guard let secContentsObj = twoCol["secondaryContents"] as? [String: Any],
                  let secList = secContentsObj["sectionListRenderer"] as? [String: Any],
                  let secItems = secList["contents"] as? [[String: Any]] else {
                return []
            }
            
            var tracks: [Track] = []
            for item in secItems {
                guard let shelf = item["musicShelfRenderer"] as? [String: Any],
                      let contents = shelf["contents"] as? [[String: Any]] else {
                    continue
                }
                
                for trk in contents {
                    guard let flex = trk["musicResponsiveListItemRenderer"] as? [String: Any],
                          let flexCols = flex["flexColumns"] as? [[String: Any]],
                          flexCols.count >= 1 else {
                        continue
                    }
                    
                    // Track Title
                    let col0 = flexCols[0]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any]
                    let col0Text = col0?["text"] as? [String: Any]
                    let col0Runs = col0Text?["runs"] as? [[String: Any]]
                    let trackTitle = col0Runs?.first?["text"] as? String ?? ""
                    guard !trackTitle.isEmpty else { continue }
                    
                    // Track Video ID
                    guard let overlay = flex["overlay"] as? [String: Any],
                          let mOverlay = overlay["musicItemThumbnailOverlayRenderer"] as? [String: Any],
                          let content = mOverlay["content"] as? [String: Any],
                          let playBtn = content["musicPlayButtonRenderer"] as? [String: Any],
                          let playNav = playBtn["playNavigationEndpoint"] as? [String: Any],
                          let watchEndpoint = playNav["watchEndpoint"] as? [String: Any],
                          let videoId = watchEndpoint["videoId"] as? String,
                          !videoId.isEmpty else {
                        continue
                    }
                    
                    // Track Artist
                    var trackArtist = defaultArtist
                    if flexCols.count > 1 {
                        let col1 = flexCols[1]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any]
                        let col1Text = col1?["text"] as? [String: Any]
                        if let subRuns = col1Text?["runs"] as? [[String: Any]] {
                            for run in subRuns {
                                if let rNav = run["navigationEndpoint"] as? [String: Any],
                                   let rBrowse = rNav["browseEndpoint"] as? [String: Any],
                                   let configs = rBrowse["browseEndpointContextSupportedConfigs"] as? [String: Any],
                                   let mConfig = configs["browseEndpointContextMusicConfig"] as? [String: Any],
                                   let pageType = mConfig["pageType"] as? String,
                                   pageType == "MUSIC_PAGE_TYPE_ARTIST" {
                                    trackArtist = run["text"] as? String ?? ""
                                    break
                                }
                            }
                        }
                    }
                    
                    // Duration
                    var durSec: Int64 = 0
                    if let fixCols = flex["fixedColumns"] as? [[String: Any]],
                       let fix0 = fixCols.first?["musicResponsiveListItemFixedColumnRenderer"] as? [String: Any],
                       let fixText = fix0["text"] as? [String: Any],
                       let fixRuns = fixText["runs"] as? [[String: Any]],
                       let durStr = fixRuns.first?["text"] as? String {
                        let parts = durStr.components(separatedBy: ":")
                        if parts.count == 2 {
                            durSec = (Int64(parts[0]) ?? 0) * 60 + (Int64(parts[1]) ?? 0)
                        } else if parts.count == 3 {
                            durSec = (Int64(parts[0]) ?? 0) * 3600 + (Int64(parts[1]) ?? 0) * 60 + (Int64(parts[2]) ?? 0)
                        }
                    }
                    
                    tracks.append(
                        Track(
                            id: videoId,
                            title: trackTitle,
                            artist: trackArtist,
                            durationSeconds: durSec,
                            thumbnailUrl: albumCover,
                            streamUrl: nil,
                            viewCount: 0,
                            likeCount: 0
                        )
                    )
                }
            }
            return tracks
        } catch {
            return []
        }
    }
}
