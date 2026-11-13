import XCTest
@testable import HarmonyCore

final class QueueAndLyricsTests: XCTestCase {
    func testSynchronizedLyricsOffsetsAndSeekPositions() {
        let lines = [LyricLine(start: 1000, value: "First"), LyricLine(start: 2000, value: "Second")]
        let early = StructuredLyrics(synced: true, offset: 100, line: lines)
        XCTAssertNil(early.activeLineIndex(at: 0.8))
        XCTAssertEqual(early.activeLineIndex(at: 0.9), 0)
        XCTAssertEqual(early.activeLineIndex(at: 1.9), 1)
        XCTAssertEqual(early.seekTime(for: 0)!, 0.9, accuracy: 0.001)
        XCTAssertEqual(early.seekTime(for: 1)!, 1.9, accuracy: 0.001)
        let late = StructuredLyrics(synced: true, offset: -100, line: lines)
        XCTAssertNil(late.activeLineIndex(at: 1))
        XCTAssertEqual(late.activeLineIndex(at: 1.1), 0)
        XCTAssertEqual(late.seekTime(for: 0)!, 1.1, accuracy: 0.001)
        XCTAssertNil(late.seekTime(for: -1))
        XCTAssertNil(late.seekTime(for: 2))
        XCTAssertNil(late.activeLineIndex(at: .nan))
        let plain = StructuredLyrics(line: [LyricLine(value: "Text")])
        XCTAssertNil(plain.activeLineIndex(at: 10))
        XCTAssertNil(plain.seekTime(for: 0))
    }

    func testQueueBoundariesRepeatAndPlayNext() throws {
        let songs = try decodeSongs()
        var queue = PlaybackQueue()
        queue.replace(songs, startingAt: 1)
        XCTAssertEqual(queue.current?.id, "2")
        queue.repeatMode = .one
        XCTAssertTrue(queue.advance(automatic: true)); XCTAssertEqual(queue.current?.id, "2")
        XCTAssertTrue(queue.advance()); XCTAssertEqual(queue.current?.id, "3")
        queue.repeatMode = .off
        XCTAssertFalse(queue.advance())
        queue.repeatMode = .all; XCTAssertTrue(queue.advance()); XCTAssertEqual(queue.current?.id, "1")
        queue.append(songs[2], next: true)
        XCTAssertTrue(queue.advance()); XCTAssertEqual(queue.current?.id, "3")
        queue.replace([])
        XCTAssertNil(queue.current)
        XCTAssertFalse(queue.advance())
    }

    func testShuffleRetainsCurrentTrackAndRestoresOrder() throws {
        let songs = try decodeSongs()
        var queue = PlaybackQueue()
        queue.replace(songs, startingAt: 1)
        queue.toggleShuffle()
        XCTAssertTrue(queue.shuffled); XCTAssertEqual(queue.current?.id, "2")
        XCTAssertEqual(Set(queue.songs.map(\.id)), Set(songs.map(\.id)))
        queue.toggleShuffle()
        XCTAssertFalse(queue.shuffled)
        XCTAssertEqual(queue.songs, songs)
        XCTAssertEqual(queue.index, 1)
    }

    func testPlayNextKeepsItsPlaceWhenShuffleToggles() throws {
        let songs = try decodeSongs()
        let extra = try JSONDecoder().decode(Song.self, from: Data(#"{"id":"4","title":"Four"}"#.utf8))
        var queue = PlaybackQueue()
        queue.replace(songs, startingAt: 0)
        queue.append(extra, next: true)
        XCTAssertEqual(queue.songs.map(\.id), ["1", "4", "2", "3"])
        queue.toggleShuffle()
        queue.toggleShuffle()
        XCTAssertEqual(queue.songs.map(\.id), ["1", "4", "2", "3"])

        queue.replace(songs, startingAt: 1)
        queue.toggleShuffle()
        queue.append(extra, next: true)
        XCTAssertEqual(queue.songs[1].id, "4")
        queue.toggleShuffle()
        XCTAssertEqual(queue.songs.map(\.id), ["1", "2", "4", "3"])
        XCTAssertEqual(queue.current?.id, "2")

        queue.toggleShuffle()
        queue.append(extra, next: false)
        queue.toggleShuffle()
        XCTAssertEqual(queue.songs.map(\.id), ["1", "2", "4", "3", "4"])
    }

    func testRemovingSongsKeepsPlaybackPosition() throws {
        let songs = try decodeSongs()
        var queue = PlaybackQueue()
        queue.replace(songs, startingAt: 1)
        XCTAssertEqual(queue.remove(["1"]), .unchanged)
        XCTAssertEqual(queue.songs.map(\.id), ["2", "3"])
        XCTAssertEqual(queue.current?.id, "2")
        XCTAssertEqual(queue.remove(["2"]), .advanced)
        XCTAssertEqual(queue.current?.id, "3")
        XCTAssertEqual(queue.remove(["3"]), .ended)
        XCTAssertNil(queue.current)
        XCTAssertEqual(queue.remove(["3"]), .unchanged)

        queue.replace(songs, startingAt: 2)
        queue.repeatMode = .all
        XCTAssertEqual(queue.remove(["3"]), .advanced)
        XCTAssertEqual(queue.current?.id, "1")

        queue.replace(songs, startingAt: 2)
        queue.repeatMode = .off
        XCTAssertEqual(queue.remove(["3"]), .ended)
        XCTAssertEqual(queue.songs.map(\.id), ["1", "2"])
    }

    func testRemovalReplacesCopiesInPlace() throws {
        let songs = try decodeSongs()
        let kept = try JSONDecoder().decode(Song.self, from: Data(#"{"id":"k","title":"Kept"}"#.utf8))
        var queue = PlaybackQueue()
        queue.replace(songs, startingAt: 1)
        XCTAssertEqual(queue.remove([], replacements: ["2": kept]), .replaced)
        XCTAssertEqual(queue.songs.map(\.id), ["1", "k", "3"])
        XCTAssertEqual(queue.current?.id, "k")
        XCTAssertEqual(queue.remove([], replacements: ["3": kept]), .unchanged)
        XCTAssertEqual(queue.songs.map(\.id), ["1", "k", "k"])
        // The unshuffled order follows the same replacements.
        queue.toggleShuffle()
        queue.toggleShuffle()
        XCTAssertEqual(queue.songs.map(\.id), ["1", "k", "k"])
    }

    private func decodeSongs() throws -> [Song] {
        try JSONDecoder().decode(
            [Song].self,
            from: Data(#"[{"id":"1","title":"One"},{"id":"2","title":"Two"},{"id":"3","title":"Three"}]"#.utf8))
    }
}
