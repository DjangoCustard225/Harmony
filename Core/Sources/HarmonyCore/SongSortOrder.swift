import Foundation

public enum SongSortOrder: String, CaseIterable, Identifiable, Sendable {
    case title, artist, album, recentlyAdded, duration
    public var id: Self { self }
    public var title: String {
        switch self {
        case .title: "Title"
        case .artist: "Artist"
        case .album: "Album"
        case .recentlyAdded: "Recently added"
        case .duration: "Duration"
        }
    }
    public var forwardLabel: String {
        switch self {
        case .title, .artist, .album: "A–Z"
        case .recentlyAdded: "Newest first"
        case .duration: "Shortest first"
        }
    }
    public var reverseLabel: String {
        switch self {
        case .title, .artist, .album: "Z–A"
        case .recentlyAdded: "Oldest first"
        case .duration: "Longest first"
        }
    }
}

extension LocalLibraryIndex {
    public func songs(sortedBy order: SongSortOrder, reversed: Bool = false) -> [Song] {
        tracks.sorted { lhs, rhs in
            let a = lhs.song, b = rhs.song
            let primary: ComparisonResult
            switch order {
            case .title: primary = a.title.localizedStandardCompare(b.title)
            case .artist: primary = a.artistName.localizedStandardCompare(b.artistName)
            case .album: primary = (a.album ?? "").localizedStandardCompare(b.album ?? "")
            case .recentlyAdded:
                if lhs.added != rhs.added { return reversed ? lhs.added < rhs.added : lhs.added > rhs.added }
                primary = .orderedSame
            case .duration:
                // Missing durations always go last, including in reverse order.
                if a.duration == nil, b.duration != nil { return false }
                if a.duration != nil, b.duration == nil { return true }
                if let a = a.duration, let b = b.duration, a != b { return reversed ? a > b : a < b }
                primary = .orderedSame
            }
            if primary != .orderedSame {
                return reversed ? primary == .orderedDescending : primary == .orderedAscending
            }
            // Keep albums in disc/track order even when the album or artist list is reversed.
            if order == .artist || order == .album {
                for pair in [
                    (a.album ?? "", b.album ?? ""), (a.albumArtist ?? a.artistName, b.albumArtist ?? b.artistName),
                ] {
                    let comparison = pair.0.localizedStandardCompare(pair.1)
                    if comparison != .orderedSame { return comparison == .orderedAscending }
                }
                if (a.discNumber ?? 1) != (b.discNumber ?? 1) { return (a.discNumber ?? 1) < (b.discNumber ?? 1) }
                if a.track != nil, b.track == nil { return true }
                if a.track == nil, b.track != nil { return false }
                if let a = a.track, let b = b.track, a != b { return a < b }
            }
            for pair in [(a.title, b.title), (a.artistName, b.artistName), (a.album ?? "", b.album ?? "")] {
                let comparison = pair.0.localizedStandardCompare(pair.1)
                if comparison != .orderedSame { return comparison == .orderedAscending }
            }
            return a.id < b.id
        }.map(\.song)
    }
}
