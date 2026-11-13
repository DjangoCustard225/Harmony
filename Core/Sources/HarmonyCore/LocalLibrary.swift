import Foundation

public struct FileFingerprint: Codable, Equatable, Sendable {
    public let sha256: String
    public let size: Int64
    public let modified: Date

    public init(sha256: String, size: Int64, modified: Date) {
        self.sha256 = sha256
        self.size = size
        self.modified = modified
    }
}

public struct LocalTrack: Codable, Identifiable, Sendable {
    public private(set) var song: Song
    /// The file's path inside Harmony's folder, or inside its linked folder when `folderID` is set.
    public private(set) var filename: String
    public private(set) var artworkFilename: String?
    public private(set) var lyrics: String?
    public let added: Date
    public let metadata: TrackMetadata?
    public let originalFilename: String?
    public let metadataVersion: Int?
    public private(set) var fingerprint: FileFingerprint?
    /// Changes the user made in Harmony, applied over the file's tags.
    public let edits: TrackEdits?
    /// The linked folder that holds this file, or nil for a copy in Harmony's own folder.
    public let folderID: String?
    public var id: String { song.id }

    public init(
        id: String = UUID().uuidString, filename: String, title: String, artist: String?,
        album: String?, albumArtist: String? = nil, duration: Int? = nil, track: Int? = nil,
        disc: Int? = nil, artworkFilename: String? = nil, lyrics: String? = nil, added: Date = Date(),
        metadata: TrackMetadata? = nil, originalFilename: String? = nil, metadataVersion: Int? = nil,
        fingerprint: FileFingerprint? = nil, edits: TrackEdits? = nil, folderID: String? = nil
    ) {
        let edits = edits?.isEmpty == true ? nil : edits
        let title = edits?.title ?? title
        let artist = edits?.artist ?? artist
        let album = edits?.album ?? album
        let albumArtist = edits?.albumArtist ?? albumArtist
        let track = edits?.track.map(TrackEdits.number) ?? track
        let disc = edits?.disc.map(TrackEdits.number) ?? disc
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
        self.fingerprint = fingerprint
        self.edits = edits
        self.folderID = folderID
    }

    /// The same song at a new path in its folder, for files moved or renamed outside Harmony.
    public func moved(to path: String) -> LocalTrack {
        var copy = self
        copy.filename = path
        return copy
    }

    public var year: Int? { edits?.year.map(TrackEdits.number) ?? metadata?.year }
    public var genre: String? { edits?.genre.map { Self.clean($0) } ?? metadata?.genre }

    /// The values the file's own tags give, before any edits.
    public var tagFields: TrackFields {
        guard let metadata else {
            // Tracks without stored tags fall back to what was indexed.
            return TrackFields(
                title: song.title, artist: song.artist ?? "", albumArtist: song.albumArtist ?? "",
                album: song.album ?? "", track: song.track, disc: song.discNumber)
        }
        let fallbackTitle = originalFilename.map {
            URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent
        }
        return TrackFields(
            title: metadata.title ?? fallbackTitle ?? song.title, artist: metadata.artist ?? "",
            albumArtist: metadata.albumArtist ?? "", album: metadata.album ?? "", genre: metadata.genre ?? "",
            track: metadata.track, disc: metadata.disc, year: metadata.year)
    }

    /// The values shown in Harmony, with edits applied.
    public var fields: TrackFields { edits?.applied(to: tagFields) ?? tagFields }

    /// This track showing `fields`; values equal to the file's tags aren't stored as edits.
    public func editing(_ fields: TrackFields) -> LocalTrack {
        let tags = tagFields
        let edits = TrackEdits(tags: tags, edited: fields)
        return LocalTrack(
            id: id, filename: filename, title: tags.title, artist: tags.artist, album: tags.album,
            albumArtist: tags.albumArtist, duration: song.duration, track: tags.track, disc: tags.disc,
            artworkFilename: artworkFilename, lyrics: lyrics, added: added, metadata: metadata,
            originalFilename: originalFilename, metadataVersion: metadataVersion, fingerprint: fingerprint,
            edits: edits, folderID: folderID)
    }
    fileprivate mutating func setArtwork(filename: String) {
        artworkFilename = filename
        song.coverArt = id
    }
    fileprivate mutating func setFingerprint(_ value: FileFingerprint?) { fingerprint = value }
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
    public private(set) var folders: [LinkedFolder]
    public init(tracks: [LocalTrack] = [], folders: [LinkedFolder] = []) {
        self.tracks = tracks
        self.folders = folders
    }

    private enum CodingKeys: String, CodingKey { case tracks, folders }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tracks = try container.decode([LocalTrack].self, forKey: .tracks)
        // Libraries saved before linked folders existed have no "folders" key.
        folders = try container.decodeIfPresent([LinkedFolder].self, forKey: .folders) ?? []
    }

    public func folder(_ id: String) -> LinkedFolder? { folders.first { $0.id == id } }
    public func tracks(inFolder id: String?) -> [LocalTrack] { tracks.filter { $0.folderID == id } }
    public mutating func addFolder(_ folder: LinkedFolder) {
        guard self.folder(folder.id) == nil else { return updateFolder(folder) }
        folders.append(folder)
    }
    public mutating func updateFolder(_ folder: LinkedFolder) {
        guard let position = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        folders[position] = folder
    }
    /// Unlinks a folder and drops its songs from the index; returns the dropped songs.
    public mutating func removeFolder(_ id: String) -> [LocalTrack] {
        let removed = tracks(inFolder: id)
        tracks.removeAll { $0.folderID == id }
        folders.removeAll { $0.id == id }
        return removed
    }
    /// Removes a linked song from the index and remembers its path, so rescans don't add it back.
    public mutating func hide(_ trackID: String) {
        guard let track = tracks.first(where: { $0.id == trackID }), let folderID = track.folderID,
            var folder = folder(folderID)
        else { return }
        if !folder.hidden.contains(track.filename) { folder.hidden.append(track.filename) }
        updateFolder(folder)
        remove(trackID)
    }
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
    public mutating func setFingerprint(_ fingerprint: FileFingerprint?, for id: String) {
        guard let position = tracks.firstIndex(where: { $0.id == id }) else { return }
        tracks[position].setFingerprint(fingerprint)
    }
    public var duplicateGroups: [[LocalTrack]] {
        let checked = tracks.filter { $0.fingerprint != nil }
        return Dictionary(grouping: checked, by: { "\($0.fingerprint!.size):\($0.fingerprint!.sha256)" }).values
            .filter { $0.count > 1 }
            .map { $0.sorted { $0.added == $1.added ? $0.id < $1.id : $0.added < $1.added } }
            .sorted { $0[0].song.title.localizedStandardCompare($1[0].song.title) == .orderedAscending }
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
                year: entries.compactMap(\.year).first,
                genre: entries.compactMap(\.genre).first,
                starred: nil, song: ordered)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    public var artists: [Artist] { Self.artists(from: albums) }
    /// Artists for already-grouped `albums`, so callers that have them don't group the library twice.
    public static func artists(from albums: [Album]) -> [Artist] {
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
