import Foundation

public struct Album: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let artist: String?
    public let displayArtist: String?
    public let artists: [ArtistCredit]?
    public let artistId: String?
    public let coverArt: String?
    public let songCount: Int?
    public let duration: Int?
    public let year: Int?
    public let genre: String?
    public var starred: String?
    public let song: [Song]?
    public var artistName: String {
        ArtistCredit.display(displayArtist, credits: artists, fallback: artist) ?? "Unknown artist"
    }
    public var songs: [Song] {
        guard let albumArtist = ArtistCredit.display(displayArtist, credits: artists, fallback: artist) else {
            return song ?? []
        }
        return (song ?? []).map { $0.withAlbumArtistFallback(albumArtist) }
    }
}

public struct Song: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let artist: String?
    public let displayAlbumArtist: String?
    public let albumArtists: [ArtistCredit]?
    public var albumArtist: String?
    public let album: String?
    public let albumId: String?
    public let artistId: String?
    public var coverArt: String?
    public let duration: Int?
    public let track: Int?
    public let discNumber: Int?
    public let suffix: String?
    public let bitRate: Int?
    public let size: Int64?
    public var starred: String?
    public var artistName: String {
        ArtistCredit.nonempty(artist)
            ?? ArtistCredit.display(displayAlbumArtist, credits: albumArtists, fallback: albumArtist)
            ?? "Unknown artist"
    }

    func withAlbumArtistFallback(_ name: String) -> Song {
        guard ArtistCredit.display(displayAlbumArtist, credits: albumArtists, fallback: albumArtist) == nil else {
            return self
        }
        var song = self
        song.albumArtist = name
        return song
    }
}

extension Album {
    public init?(song: Song) {
        guard let id = song.albumId, !id.isEmpty else { return nil }
        self.init(
            id: id, name: song.album ?? "Unknown album", artist: song.artistName,
            displayArtist: song.displayAlbumArtist, artists: song.albumArtists,
            artistId: song.albumArtists?.compactMap(\.id).first
                ?? (song.artist == song.artistName ? song.artistId : nil),
            coverArt: song.coverArt, songCount: nil, duration: nil, year: nil, genre: nil, starred: nil, song: nil)
    }
}

public struct ArtistCredit: Codable, Hashable, Sendable {
    public let id: String?
    public let name: String

    static func nonempty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    static func display(_ display: String?, credits: [ArtistCredit]?, fallback: String?) -> String? {
        if let display = nonempty(display) { return display }
        var seen = Set<String>()
        let names = (credits ?? []).compactMap { nonempty($0.name) }.filter { seen.insert($0).inserted }
        if !names.isEmpty { return names.joined(separator: ", ") }
        return nonempty(fallback)
    }
}

public struct Artist: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let coverArt: String?
    public let albumCount: Int?
    public let album: [Album]?
    public var albums: [Album] { album ?? [] }
    public init(id: String, name: String, coverArt: String? = nil, albumCount: Int? = nil, album: [Album]? = nil) {
        self.id = id
        self.name = name
        self.coverArt = coverArt
        self.albumCount = albumCount
        self.album = album
    }
}

public struct SearchResults: Codable, Sendable {
    public let album: [Album]?
    public let artist: [Artist]?
    public let song: [Song]?
    public var albums: [Album] { album ?? [] }
    public var artists: [Artist] { artist ?? [] }
    public var songs: [Song] { song ?? [] }
    public var isEmpty: Bool { albums.isEmpty && artists.isEmpty && songs.isEmpty }
    public init(album: [Album] = [], artist: [Artist] = [], song: [Song] = []) {
        self.album = album
        self.artist = artist
        self.song = song
    }
}

public enum AlbumOrder: String, CaseIterable, Identifiable, Sendable {
    case alphabeticalByName, newest
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .alphabeticalByName: "A–Z"
        case .newest: "Recently added"
        }
    }
}

public enum TimeLabel {
    public static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let value = Int(max(0, seconds))
        return String(format: "%d:%02d", value / 60, value % 60)
    }

    public static func duration(_ seconds: Int) -> String {
        seconds >= 3600 ? "\(seconds / 3600) hr \((seconds % 3600) / 60) min" : "\(max(0, seconds) / 60) min"
    }
}
