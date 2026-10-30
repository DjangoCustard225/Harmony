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

    private func decodeSongs() throws -> [Song] {
        try JSONDecoder().decode(
            [Song].self,
            from: Data(#"[{"id":"1","title":"One"},{"id":"2","title":"Two"},{"id":"3","title":"Three"}]"#.utf8))
    }
}
