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
    
    /// Auto-upscale low-res thumbnails to sharp 500x500 or hqdefault without 404 risk (1:1 Android)
    var highResThumbnailUrl: String {
        // 0. Cek file cover lokal offline terlebih dahulu (100% offline, tanpa internet)
        if let localCover = DownloadService.shared.getLocalCoverFileUrl(for: id) {
            return localCover.absoluteString
        }
        
        var url = thumbnailUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. Bersihkan path lokal Android (/data/user/0/...) jika terbawa di thumbnail
        if url.hasPrefix("/data/") || url.hasPrefix("file://") {
            url = ""
        }
        
        // 2. Jika thumbnailUrl kosong, buat fallback langsung dari track ID YouTube
        if url.isEmpty {
            if !id.hasPrefix("dz_") && id.count == 11 {
                return "https://i.ytimg.com/vi/\(id)/hqdefault.jpg"
            }
        }
        
        if url.contains("deezer.com") {
            // Deezer 500x500 is 100% available across all tracks and albums without 404
            url = url.replacingOccurrences(of: "/250x250-", with: "/500x500-")
            url = url.replacingOccurrences(of: "/120x120-", with: "/500x500-")
            url = url.replacingOccurrences(of: "/56x56-", with: "/500x500-")
        } else if url.contains("ytimg.com") || url.contains("ggpht.com") {
            // hqdefault and sddefault are always available on YouTube servers (maxresdefault often 404s)
            url = url.replacingOccurrences(of: "default.jpg", with: "hqdefault.jpg")
            url = url.replacingOccurrences(of: "mqdefault.jpg", with: "hqdefault.jpg")
            url = url.replacingOccurrences(of: "=w120-h120", with: "=w600-h600")
            url = url.replacingOccurrences(of: "=s120", with: "=s600")
            url = url.replacingOccurrences(of: "=s60", with: "=s600")
        }
        return url
    }
}

extension DeezerTrack {
    var highResCoverUrl: String {
        var url = coverUrl
        if url.contains("deezer.com") {
            url = url.replacingOccurrences(of: "/250x250-", with: "/500x500-")
            url = url.replacingOccurrences(of: "/120x120-", with: "/500x500-")
            url = url.replacingOccurrences(of: "/56x56-", with: "/500x500-")
        }
        return url
    }
}

extension DeezerAlbum {
    var highResCoverUrl: String {
        var url = coverUrl
        if url.contains("deezer.com") {
            url = url.replacingOccurrences(of: "/250x250-", with: "/500x500-")
            url = url.replacingOccurrences(of: "/120x120-", with: "/500x500-")
            url = url.replacingOccurrences(of: "/56x56-", with: "/500x500-")
        }
        return url
    }
}

extension DeezerArtist {
    var highResPictureUrl: String {
        var url = pictureUrl
        if url.contains("deezer.com") {
            url = url.replacingOccurrences(of: "/250x250-", with: "/500x500-")
            url = url.replacingOccurrences(of: "/120x120-", with: "/500x500-")
            url = url.replacingOccurrences(of: "/56x56-", with: "/500x500-")
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
