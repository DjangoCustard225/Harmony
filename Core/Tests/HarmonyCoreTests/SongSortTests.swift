import XCTest
@testable import HarmonyCore

final class SongSortTests: XCTestCase {
    func testNaturalTitleSortingInBothDirections() {
        let library = LocalLibraryIndex(tracks: [
            track("ten", title: "Song 10"), track("two", title: "Song 2"), track("one", title: "Song 1"),
        ])
        XCTAssertEqual(library.songs(sortedBy: .title).map(\.id), ["one", "two", "ten"])
        XCTAssertEqual(library.songs(sortedBy: .title, reversed: true).map(\.id), ["ten", "two", "one"])
    }
    func testAlbumAndArtistSortKeepDiscAndTrackSequence() {
        let library = LocalLibraryIndex(tracks: [
            track("disc2", title: "First", artist: "Band", album: "Alpha", number: 1, disc: 2),
            track("track2", title: "Beta", artist: "Band", album: "Alpha", number: 2, disc: 1),
            track("track1", title: "Zulu", artist: "Band", album: "Alpha", number: 1, disc: 1),
            track("other", title: "Other", artist: "Another", album: "Zebra", number: 1),
        ])
        XCTAssertEqual(library.songs(sortedBy: .album).map(\.id), ["track1", "track2", "disc2", "other"])
        XCTAssertEqual(
            library.songs(sortedBy: .album, reversed: true).map(\.id), ["other", "track1", "track2", "disc2"])
        XCTAssertEqual(library.songs(sortedBy: .artist).map(\.id), ["other", "track1", "track2", "disc2"])
        XCTAssertEqual(
            library.songs(sortedBy: .artist, reversed: true).map(\.id), ["track1", "track2", "disc2", "other"])
    }
    func testSameNamedAlbumsFromDifferentArtistsDoNotInterleave() {
        let library = LocalLibraryIndex(tracks: [
            track("b1", title: "First", artist: "B", album: "Live", number: 1),
            track("a2", title: "Second", artist: "A", album: "Live", number: 2),
            track("a1", title: "First", artist: "A", album: "Live", number: 1),
        ])
        XCTAssertEqual(library.songs(sortedBy: .album).map(\.id), ["a1", "a2", "b1"])
    }
    func testImportDateSortingAndDeterministicTies() {
        let library = LocalLibraryIndex(tracks: [
            track("old", title: "Old", added: 100), track("z", title: "Zulu", added: 200),
            track("a", title: "Alpha", added: 200),
        ])
        XCTAssertEqual(library.songs(sortedBy: .recentlyAdded).map(\.id), ["a", "z", "old"])
        XCTAssertEqual(library.songs(sortedBy: .recentlyAdded, reversed: true).map(\.id), ["old", "a", "z"])
    }
    func testDurationSortingPutsMissingLengthsLastInBothDirections() {
        let library = LocalLibraryIndex(tracks: [
            track("unknown", title: "Unknown"), track("long", title: "Long", duration: 200),
            track("short", title: "Short", duration: 30),
        ])
        XCTAssertEqual(library.songs(sortedBy: .duration).map(\.id), ["short", "long", "unknown"])
        XCTAssertEqual(library.songs(sortedBy: .duration, reversed: true).map(\.id), ["long", "short", "unknown"])
        XCTAssertTrue(LocalLibraryIndex().songs(sortedBy: .duration).isEmpty)
    }
    func testPlaybackQueueFollowsChosenSongOrder() {
        let library = LocalLibraryIndex(tracks: [
            track("a", title: "A"), track("b", title: "B"), track("c", title: "C"),
        ])
        let songs = library.songs(sortedBy: .title, reversed: true)
        var queue = PlaybackQueue()
        queue.replace(songs, startingAt: 1)
        XCTAssertEqual(queue.current?.id, "b")
        XCTAssertTrue(queue.advance())
        XCTAssertEqual(queue.current?.id, "a")
        XCTAssertFalse(queue.advance())
    }
    private func track(
        _ id: String, title: String, artist: String = "Artist", album: String = "Album", duration: Int? = nil,
        number: Int? = nil, disc: Int? = nil, added: TimeInterval = 100
    ) -> LocalTrack {
        LocalTrack(
            id: id, filename: id + ".flac", title: title, artist: artist, album: album,
            duration: duration, track: number, disc: disc, added: Date(timeIntervalSince1970: added))
    }
}
