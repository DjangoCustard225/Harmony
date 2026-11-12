import Foundation

public enum RepeatMode: String, CaseIterable, Sendable { case off, all, one }

public struct PlaybackQueue: Sendable {
    public private(set) var songs: [Song] = []
    public private(set) var index: Int = 0
    public var repeatMode: RepeatMode = .off
    public private(set) var shuffled = false
    private var original: [Song] = []
    public var current: Song? { songs.indices.contains(index) ? songs[index] : nil }
    public init() {}
    public mutating func replace(_ songs: [Song], startingAt index: Int = 0, shuffle: Bool = false) {
        original = songs
        self.songs = songs
        self.index = max(0, min(index, songs.count - 1))
        shuffled = shuffle
        if shuffle, let current {
            self.songs = [current] + songs.enumerated().filter { $0.offset != self.index }.map(\.element).shuffled()
            self.index = 0
        }
    }
    public mutating func refreshMetadata(_ updated: [Song]) {
        let byID = updated.reduce(into: [String: Song]()) { $0[$1.id] = $1 }
        songs = songs.map { byID[$0.id] ?? $0 }
        original = original.map { byID[$0.id] ?? $0 }
    }
    public mutating func advance(automatic: Bool = false) -> Bool {
        guard !songs.isEmpty else { return false }
        if automatic && repeatMode == .one { return true }
        if index + 1 < songs.count {
            index += 1
            return true
        }
        if repeatMode == .all {
            index = 0
            return true
        }
        return false
    }
    public mutating func previous() { index = max(0, index - 1) }
    public mutating func select(_ index: Int) { if songs.indices.contains(index) { self.index = index } }
    public mutating func append(_ song: Song, next: Bool) {
        let playing = current
        songs.insert(song, at: next && !songs.isEmpty ? index + 1 : songs.count)
        // Keep the unshuffled order in step so "Play next" survives toggling shuffle.
        if !shuffled {
            original = songs
        } else if next, let playing, let position = original.firstIndex(where: { $0.id == playing.id }) {
            original.insert(song, at: position + 1)
        } else {
            original.append(song)
        }
    }
    public enum Removal: Equatable, Sendable {
        /// The current song is unaffected.
        case unchanged
        /// The current song was swapped for its replacement (for example a kept duplicate copy).
        case replaced
        /// The current song was removed and the following song is now current.
        case advanced
        /// Nothing is left to play after the current song.
        case ended
    }

    /// Removes songs, or swaps in their replacements, keeping the current position in the queue.
    /// When the current song is removed, the next remaining song becomes current, wrapping with repeat-all.
    public mutating func remove(_ ids: Set<String>, replacements: [String: Song] = [:]) -> Removal {
        guard let playing = current else { return .unchanged }
        func survives(_ song: Song) -> Bool { replacements[song.id] != nil || !ids.contains(song.id) }
        func filtered(_ list: [Song]) -> [Song] {
            list.compactMap { song in replacements[song.id] ?? (ids.contains(song.id) ? nil : song) }
        }
        // Songs before the current one that remain; this is the current song's new position.
        let before = songs[..<index].filter(survives).count
        songs = filtered(songs)
        original = filtered(original)
        if let replacement = replacements[playing.id] {
            index = before
            return replacement.id == playing.id ? .unchanged : .replaced
        }
        if !ids.contains(playing.id) {
            index = before
            return .unchanged
        }
        if before < songs.count {
            index = before
            return .advanced
        }
        if repeatMode == .all, !songs.isEmpty {
            index = 0
            return .advanced
        }
        index = max(0, songs.count - 1)
        return .ended
    }

    public mutating func toggleShuffle() {
        guard let current else { return }
        if shuffled {
            songs = original
            index = songs.firstIndex(where: { $0.id == current.id }) ?? 0
        } else {
            songs = [current] + songs.enumerated().filter { $0.offset != index }.map(\.element).shuffled()
            index = 0
        }
        shuffled.toggle()
    }
}
