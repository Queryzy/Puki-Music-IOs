import Foundation

struct Track: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let artist: String
    let durationSeconds: Int64
    let thumbnailUrl: String
    var streamUrl: String? = nil
    var viewCount: Int64 = 0
    var likeCount: Int64 = 0
    
    var formattedDuration: String {
        let minutes = durationSeconds / 60
        let seconds = durationSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct Album: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let artist: String
    let trackCount: Int64
    let thumbnailUrl: String
    let url: String
}

struct DeezerTrack: Identifiable, Codable {
    let id: Int64
    let title: String
    let artistName: String
    let artistId: Int64
    let albumTitle: String
    let albumId: Int64
    let durationSeconds: Int64
    let coverUrl: String
    let isrc: String?
    let previewUrl: String?
}

struct DeezerAlbum: Identifiable, Codable {
    let id: Int64
    let title: String
    let coverUrl: String
    let artistName: String
    let artistId: Int64
    let releaseDate: String?
    let trackCount: Int
    let recordType: String
}

struct DeezerArtist: Identifiable, Codable {
    let id: Int64
    let name: String
    let pictureUrl: String
    let fanCount: Int
    let albumCount: Int
}

struct DeezerDashboardData {
    var topTracks: [DeezerTrack] = []
    var topAlbums: [DeezerAlbum] = []
    var topArtists: [DeezerArtist] = []
}
