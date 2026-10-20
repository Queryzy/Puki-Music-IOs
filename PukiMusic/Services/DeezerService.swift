import Foundation

class DeezerService {
    static let shared = DeezerService()
    private let baseURL = "https://api.deezer.com"
    private let session = URLSession.shared
    
    func getDashboardCharts() async throws -> DeezerDashboardData {
        guard let url = URL(string: "\(baseURL)/chart/0") else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await session.data(from: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return DeezerDashboardData()
        }
        
        var dashboard = DeezerDashboardData()
        
        // Parse Tracks
        if let tracksObj = json["tracks"] as? [String: Any],
           let items = tracksObj["data"] as? [[String: Any]] {
            dashboard.topTracks = items.compactMap { parseTrack($0) }
        }
        
        // Parse Albums
        if let albumsObj = json["albums"] as? [String: Any],
           let items = albumsObj["data"] as? [[String: Any]] {
            dashboard.topAlbums = items.compactMap { parseAlbum($0) }
        }
        
        // Parse Artists
        if let artistsObj = json["artists"] as? [String: Any],
           let items = artistsObj["data"] as? [[String: Any]] {
            dashboard.topArtists = items.compactMap { parseArtist($0) }
        }
        
        return dashboard
    }
    
    func searchTracks(query: String, limit: Int = 30) async throws -> [DeezerTrack] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseURL)/search/track?q=\(encoded)&limit=\(limit)") else {
            return []
        }
        
        let (data, _) = try await session.data(from: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]] else {
            return []
        }
        
        return items.compactMap { parseTrack($0) }
    }
    
    func searchAlbums(query: String, limit: Int = 20) async throws -> [DeezerAlbum] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseURL)/search/album?q=\(encoded)&limit=\(limit)") else {
            return []
        }
        
        let (data, _) = try await session.data(from: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]] else {
            return []
        }
        
        return items.compactMap { parseAlbum($0) }
    }
    
    private func parseTrack(_ item: [String: Any]) -> DeezerTrack? {
        guard let id = item["id"] as? Int64 ?? (item["id"] as? Int).map({ Int64($0) }),
              let title = item["title"] as? String else { return nil }
        
        let artistObj = item["artist"] as? [String: Any]
        let artistName = artistObj?["name"] as? String ?? "Artis Tidak Dikenal"
        let artistId = artistObj?["id"] as? Int64 ?? (artistObj?["id"] as? Int).map({ Int64($0) }) ?? 0
        
        let albumObj = item["album"] as? [String: Any]
        let albumTitle = albumObj?["title"] as? String ?? ""
        let albumId = albumObj?["id"] as? Int64 ?? (albumObj?["id"] as? Int).map({ Int64($0) }) ?? 0
        
        let cover = albumObj?["cover_big"] as? String ??
                    albumObj?["cover_medium"] as? String ??
                    albumObj?["cover"] as? String ?? ""
        
        let duration = item["duration"] as? Int64 ?? (item["duration"] as? Int).map({ Int64($0) }) ?? 0
        let isrc = item["isrc"] as? String
        
        return DeezerTrack(
            id: id,
            title: title,
            artistName: artistName,
            artistId: artistId,
            albumTitle: albumTitle,
            albumId: albumId,
            durationSeconds: duration,
            coverUrl: cover,
            isrc: isrc
        )
    }
    
    private func parseAlbum(_ item: [String: Any]) -> DeezerAlbum? {
        guard let id = item["id"] as? Int64 ?? (item["id"] as? Int).map({ Int64($0) }),
              let title = item["title"] as? String else { return nil }
        
        let artistObj = item["artist"] as? [String: Any]
        let artistName = artistObj?["name"] as? String ?? ""
        let artistId = artistObj?["id"] as? Int64 ?? (artistObj?["id"] as? Int).map({ Int64($0) }) ?? 0
        
        let cover = item["cover_big"] as? String ??
                    item["cover_medium"] as? String ??
                    item["cover"] as? String ?? ""
        
        let trackCount = item["nb_tracks"] as? Int ?? 0
        let releaseDate = item["release_date"] as? String
        let recordType = item["record_type"] as? String ?? "album"
        
        return DeezerAlbum(
            id: id,
            title: title,
            coverUrl: cover,
            artistName: artistName,
            artistId: artistId,
            releaseDate: releaseDate,
            trackCount: trackCount,
            recordType: recordType
        )
    }
    
    private func parseArtist(_ item: [String: Any]) -> DeezerArtist? {
        guard let id = item["id"] as? Int64 ?? (item["id"] as? Int).map({ Int64($0) }),
              let name = item["name"] as? String else { return nil }
        
        let picture = item["picture_big"] as? String ??
                      item["picture_medium"] as? String ??
                      item["picture"] as? String ?? ""
        
        let fanCount = item["nb_fan"] as? Int ?? 0
        let albumCount = item["nb_album"] as? Int ?? 0
        
        return DeezerArtist(
            id: id,
            name: name,
            pictureUrl: picture,
            fanCount: fanCount,
            albumCount: albumCount
        )
    }
}
