import Foundation

/// A track's editable values. Empty text and nil numbers mean "not set".
public struct TrackFields: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var albumArtist: String
    public var album: String
    public var genre: String
    public var track: Int?
    public var disc: Int?
    public var year: Int?

    public init(
        title: String = "", artist: String = "", albumArtist: String = "", album: String = "", genre: String = "",
        track: Int? = nil, disc: Int? = nil, year: Int? = nil
    ) {
        self.title = title
        self.artist = artist
        self.albumArtist = albumArtist
        self.album = album
        self.genre = genre
        self.track = track
        self.disc = disc
        self.year = year
    }
}

/// Overrides stored in the library, so a metadata refresh keeps them and the file isn't changed.
/// A nil field keeps the file's tag; an empty string or 0 clears it.
public struct TrackEdits: Codable, Equatable, Sendable {
    public var title: String?
    public var artist: String?
    public var albumArtist: String?
    public var album: String?
    public var genre: String?
    public var track: Int?
    public var disc: Int?
    public var year: Int?

    public init() {}

    /// The differences between `edited` and `tags`, or nil when there are none.
    public init?(tags: TrackFields, edited: TrackFields) {
        func text(_ tag: String, _ value: String) -> String? {
            let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return value == tag.trimmingCharacters(in: .whitespacesAndNewlines) ? nil : value
        }
        func number(_ tag: Int?, _ value: Int?) -> Int? {
            let value = value.flatMap { $0 > 0 ? $0 : nil }
            return value == tag ? nil : value ?? 0
        }
        title = text(tags.title, edited.title)
        artist = text(tags.artist, edited.artist)
        albumArtist = text(tags.albumArtist, edited.albumArtist)
        album = text(tags.album, edited.album)
        genre = text(tags.genre, edited.genre)
        track = number(tags.track, edited.track)
        disc = number(tags.disc, edited.disc)
        year = number(tags.year, edited.year)
        if isEmpty { return nil }
    }

    public var isEmpty: Bool { self == TrackEdits() }

    public func applied(to tags: TrackFields) -> TrackFields {
        TrackFields(
            title: title ?? tags.title, artist: artist ?? tags.artist, albumArtist: albumArtist ?? tags.albumArtist,
            album: album ?? tags.album, genre: genre ?? tags.genre, track: track.map(Self.number) ?? tags.track,
            disc: disc.map(Self.number) ?? tags.disc, year: year.map(Self.number) ?? tags.year)
    }

    /// A stored number, where 0 means cleared.
    static func number(_ value: Int) -> Int? { value > 0 ? value : nil }
}
