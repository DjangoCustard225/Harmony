import Foundation

public struct Playlist: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public fileprivate(set) var name: String
    /// Library song IDs in play order. A song may appear more than once.
    public fileprivate(set) var songIDs: [String]
    public let created: Date
    public fileprivate(set) var modified: Date

    public init(
        id: String = UUID().uuidString, name: String, songIDs: [String] = [], created: Date = Date(),
        modified: Date? = nil
    ) {
        self.id = id
        self.name = PlaylistCollection.cleanName(name)
        self.songIDs = songIDs
        self.created = created
        self.modified = modified ?? created
    }
}

public struct PlaylistEntry: Hashable, Sendable {
    /// Index in the playlist's `songIDs`.
    public let position: Int
    public let song: Song
}

public struct PlaylistCollection: Codable, Sendable {
    public static let defaultName = "New Playlist"
    public private(set) var playlists: [Playlist]

    public init(playlists: [Playlist] = []) { self.playlists = playlists }

    public func playlist(_ id: String) -> Playlist? { playlists.first { $0.id == id } }

    @discardableResult
    public mutating func create(name: String, songIDs: [String] = [], now: Date = Date()) -> Playlist {
        let playlist = Playlist(name: name, songIDs: songIDs, created: now)
        playlists.append(playlist)
        return playlist
    }

    public mutating func rename(_ id: String, to name: String, now: Date = Date()) {
        update(id, now: now) { $0.name = Self.cleanName(name) }
    }

    public mutating func delete(_ id: String) { playlists.removeAll { $0.id == id } }

    public mutating func add(_ songIDs: [String], to id: String, now: Date = Date()) {
        guard !songIDs.isEmpty else { return }
        update(id, now: now) { $0.songIDs.append(contentsOf: songIDs) }
    }

    /// Removes the entries at `offsets` (positions in the playlist, not song IDs).
    public mutating func remove(at offsets: IndexSet, from id: String, now: Date = Date()) {
        update(id, now: now) { playlist in
            for offset in offsets.sorted(by: >) where playlist.songIDs.indices.contains(offset) {
                playlist.songIDs.remove(at: offset)
            }
        }
    }

    /// Moves entries with the same meaning as SwiftUI's `onMove`: `destination` is an index in the
    /// list before the move.
    public mutating func move(from offsets: IndexSet, to destination: Int, in id: String, now: Date = Date()) {
        update(id, now: now) { playlist in
            let valid = offsets.filter { playlist.songIDs.indices.contains($0) }
            guard !valid.isEmpty else { return }
            let moving = valid.map { playlist.songIDs[$0] }
            let target = min(max(0, destination), playlist.songIDs.count)
            let shift = valid.filter { $0 < target }.count
            for offset in valid.sorted(by: >) { playlist.songIDs.remove(at: offset) }
            playlist.songIDs.insert(contentsOf: moving, at: target - shift)
        }
    }

    /// Drops songs that left the library. Returns whether anything changed.
    @discardableResult
    public mutating func removeSongs(_ ids: Set<String>, now: Date = Date()) -> Bool {
        guard !ids.isEmpty else { return false }
        var changed = false
        for index in playlists.indices where playlists[index].songIDs.contains(where: ids.contains) {
            playlists[index].songIDs.removeAll(where: ids.contains)
            playlists[index].modified = now
            changed = true
        }
        return changed
    }

    /// Points entries for a removed copy at the copy that was kept, in the same positions.
    @discardableResult
    public mutating func replaceSong(_ old: String, with new: String, now: Date = Date()) -> Bool {
        guard old != new else { return false }
        var changed = false
        for index in playlists.indices where playlists[index].songIDs.contains(old) {
            playlists[index].songIDs = playlists[index].songIDs.map { $0 == old ? new : $0 }
            playlists[index].modified = now
            changed = true
        }
        return changed
    }

    /// The playlist's songs that are still in the library, in playlist order, with each entry's
    /// position in `songIDs` so edits made on the visible list apply to the right stored entry.
    public static func entries(in playlist: Playlist, library: LocalLibraryIndex) -> [PlaylistEntry] {
        entries(
            in: playlist, songs: Dictionary(library.tracks.map { ($0.id, $0.song) }, uniquingKeysWith: { a, _ in a }))
    }

    /// Same as `entries(in:library:)` with a prebuilt ID lookup, for resolving many playlists.
    public static func entries(in playlist: Playlist, songs byID: [String: Song]) -> [PlaylistEntry] {
        playlist.songIDs.enumerated().compactMap { position, id in
            byID[id].map { PlaylistEntry(position: position, song: $0) }
        }
    }

    public static func songs(in playlist: Playlist, library: LocalLibraryIndex) -> [Song] {
        entries(in: playlist, library: library).map(\.song)
    }

    /// Converts a move on the visible entries into a move on the stored list.
    public static func storedMove(
        from offsets: IndexSet, to destination: Int, entries: [PlaylistEntry], storedCount: Int
    ) -> (offsets: IndexSet, destination: Int) {
        let stored = IndexSet(offsets.compactMap { entries.indices.contains($0) ? entries[$0].position : nil })
        let target = entries.indices.contains(destination) ? entries[destination].position : storedCount
        return (stored, target)
    }

    static func cleanName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultName : trimmed
    }

    private mutating func update(_ id: String, now: Date, _ change: (inout Playlist) -> Void) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        change(&playlists[index])
        playlists[index].modified = now
    }
}
