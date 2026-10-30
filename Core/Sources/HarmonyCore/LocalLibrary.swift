import Foundation

public struct LocalTrack: Codable, Identifiable, Sendable {
    public private(set) var song: Song
    public let filename: String
    public private(set) var artworkFilename: String?
    public private(set) var lyrics: String?
    public let added: Date
    public let metadata: TrackMetadata?
    public let originalFilename: String?
    public let metadataVersion: Int?
    public var id: String { song.id }

    public init(
        id: String = UUID().uuidString, filename: String, title: String, artist: String?,
        album: String?, albumArtist: String? = nil, duration: Int? = nil, track: Int? = nil,
        disc: Int? = nil, artworkFilename: String? = nil, lyrics: String? = nil, added: Date = Date(),
        metadata: TrackMetadata? = nil, originalFilename: String? = nil, metadataVersion: Int? = nil
    ) {
        let performer = Self.clean(artist) ?? Self.clean(albumArtist) ?? "Unknown artist"
        let albumPerformer = Self.clean(albumArtist) ?? performer
        let albumName = Self.clean(album) ?? "Unknown album"
        let artistID = Self.key([albumPerformer])
        let albumID = Self.key([albumPerformer, albumName])
        self.song = Song(
            id: id, title: Self.clean(title) ?? "Untitled", artist: performer,
            displayAlbumArtist: nil, albumArtists: nil, albumArtist: albumPerformer,
            album: albumName, albumId: albumID, artistId: artistID,
            coverArt: artworkFilename == nil ? nil : id, duration: duration, track: track,
            discNumber: disc, suffix: URL(fileURLWithPath: filename).pathExtension,
            bitRate: metadata.flatMap { value in
                guard let size = value.fileSize, let seconds = value.duration, seconds > 0 else { return nil }
                return Int(Double(size) * 8 / seconds / 1000)
            }, size: metadata?.fileSize, starred: nil)
        self.filename = filename
        self.artworkFilename = artworkFilename
        self.lyrics = lyrics
        self.added = added
        self.metadata = metadata
        self.originalFilename = originalFilename
        self.metadataVersion = metadataVersion
    }
    fileprivate mutating func setArtwork(filename: String) {
        artworkFilename = filename
        song.coverArt = id
    }
    private static func clean(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
    private static func key(_ parts: [String]) -> String {
        // Length prefixes avoid collisions when names contain separators.
        parts.map {
            let s = $0.folding(
                options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"));
            return "\(s.utf8.count):\(s)"
        }.joined()
    }
}

public struct LocalLibraryIndex: Codable, Sendable {
    public private(set) var tracks: [LocalTrack]
    public init(tracks: [LocalTrack] = []) { self.tracks = tracks }
    public mutating func append(_ track: LocalTrack) { tracks.append(track) }
    public mutating func remove(_ id: String) { tracks.removeAll { $0.id == id } }
    public mutating func setArtwork(for id: String, filename: String) {
        guard let position = tracks.firstIndex(where: { $0.id == id }) else { return }
        tracks[position].setArtwork(filename: filename)
    }
    public mutating func replace(_ track: LocalTrack) {
        guard let position = tracks.firstIndex(where: { $0.id == track.id }) else { return }
        tracks[position] = track
    }
    public var songs: [Song] {
        tracks.map(\.song).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    public var albums: [Album] {
        Dictionary(grouping: tracks, by: { $0.song.albumId ?? "" }).map { id, entries in
            let ordered = entries.map(\.song).sorted {
                if ($0.discNumber ?? 1) != ($1.discNumber ?? 1) { return ($0.discNumber ?? 1) < ($1.discNumber ?? 1) }
                if ($0.track ?? 0) != ($1.track ?? 0) { return ($0.track ?? 0) < ($1.track ?? 0) }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            let first = ordered[0]
            return Album(
                id: id, name: first.album ?? "Unknown album", artist: first.albumArtist ?? first.artistName,
                displayArtist: nil, artists: nil, artistId: first.artistId,
                coverArt: ordered.compactMap(\.coverArt).first, songCount: ordered.count,
                duration: ordered.reduce(0) { $0 + ($1.duration ?? 0) },
                year: entries.compactMap { $0.metadata?.year }.first,
                genre: entries.compactMap { $0.metadata?.genre }.first,
                starred: nil, song: ordered)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    public var artists: [Artist] {
        Dictionary(grouping: albums, by: { $0.artistId ?? "" }).map { id, albums in
            Artist(
                id: id, name: albums[0].artistName, coverArt: albums.compactMap(\.coverArt).first,
                albumCount: albums.count, album: albums)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    public func search(_ query: String) -> SearchResults {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return SearchResults() }
        return SearchResults(
            album: albums.filter {
                $0.name.localizedStandardContains(term) || $0.artistName.localizedStandardContains(term)
            },
            artist: artists.filter { $0.name.localizedStandardContains(term) },
            song: songs.filter {
                $0.title.localizedStandardContains(term) || $0.artistName.localizedStandardContains(term)
                    || ($0.albumArtist?.localizedStandardContains(term) ?? false)
                    || ($0.album?.localizedStandardContains(term) ?? false)
            })
    }
}
