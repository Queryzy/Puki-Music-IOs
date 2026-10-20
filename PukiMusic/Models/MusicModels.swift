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
    
    /// Auto-upscale low-res thumbnails to 1000x1000 or maxresdefault for Retina displays (1:1 Android)
    var highResThumbnailUrl: String {
        var url = thumbnailUrl
        if url.contains("deezer.com") {
            // Replace any size with /1000x1000-
            url = url.replacingOccurrences(of: "/250x250-", with: "/1000x1000-")
            url = url.replacingOccurrences(of: "/500x500-", with: "/1000x1000-")
            url = url.replacingOccurrences(of: "/120x120-", with: "/1000x1000-")
            url = url.replacingOccurrences(of: "/56x56-", with: "/1000x1000-")
        } else if url.contains("ytimg.com") || url.contains("ggpht.com") {
            url = url.replacingOccurrences(of: "hqdefault.jpg", with: "maxresdefault.jpg")
            url = url.replacingOccurrences(of: "mqdefault.jpg", with: "maxresdefault.jpg")
            url = url.replacingOccurrences(of: "sddefault.jpg", with: "maxresdefault.jpg")
            url = url.replacingOccurrences(of: "default.jpg", with: "maxresdefault.jpg")
            url = url.replacingOccurrences(of: "=w120-h120", with: "=w1000-h1000")
            url = url.replacingOccurrences(of: "=s120", with: "=s1000")
            url = url.replacingOccurrences(of: "=s60", with: "=s1000")
        }
        return url
    }
}

extension DeezerTrack {
    var highResCoverUrl: String {
        var url = coverUrl
        if url.contains("deezer.com") {
            url = url.replacingOccurrences(of: "/250x250-", with: "/1000x1000-")
            url = url.replacingOccurrences(of: "/500x500-", with: "/1000x1000-")
            url = url.replacingOccurrences(of: "/120x120-", with: "/1000x1000-")
        }
        return url
    }
}

extension DeezerAlbum {
    var highResCoverUrl: String {
        var url = coverUrl
        if url.contains("deezer.com") {
            url = url.replacingOccurrences(of: "/250x250-", with: "/1000x1000-")
            url = url.replacingOccurrences(of: "/500x500-", with: "/1000x1000-")
            url = url.replacingOccurrences(of: "/120x120-", with: "/1000x1000-")
        }
        return url
    }
}

extension DeezerArtist {
    var highResPictureUrl: String {
        var url = pictureUrl
        if url.contains("deezer.com") {
            url = url.replacingOccurrences(of: "/250x250-", with: "/1000x1000-")
            url = url.replacingOccurrences(of: "/500x500-", with: "/1000x1000-")
            url = url.replacingOccurrences(of: "/120x120-", with: "/1000x1000-")
        }
        return url
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
