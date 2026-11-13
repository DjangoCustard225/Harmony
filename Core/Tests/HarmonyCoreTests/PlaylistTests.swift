import XCTest
@testable import HarmonyCore

final class PlaylistTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 100)
    private let later = Date(timeIntervalSince1970: 200)

    func testCreateTrimsNamesAndFallsBackToDefault() {
        var playlists = PlaylistCollection()
        let named = playlists.create(name: "  Road trip \n", songIDs: ["a"], now: start)
        let blank = playlists.create(name: "   ", now: start)
        XCTAssertEqual(named.name, "Road trip")
        XCTAssertEqual(blank.name, PlaylistCollection.defaultName)
        XCTAssertEqual(playlists.playlists.map(\.id), [named.id, blank.id])
        XCTAssertEqual(named.created, start)
        XCTAssertEqual(named.modified, start)

        playlists.rename(named.id, to: " ", now: later)
        XCTAssertEqual(playlists.playlist(named.id)?.name, PlaylistCollection.defaultName)
        XCTAssertEqual(playlists.playlist(named.id)?.modified, later)
        playlists.rename(named.id, to: "Gym", now: later)
        XCTAssertEqual(playlists.playlist(named.id)?.name, "Gym")

        playlists.delete(blank.id)
        XCTAssertEqual(playlists.playlists.map(\.id), [named.id])
    }

    func testAddRemoveAndMoveKeepOrder() {
        var playlists = PlaylistCollection()
        let id = playlists.create(name: "Mix", songIDs: ["a", "b"], now: start).id
        playlists.add(["c", "a"], to: id, now: later)
        XCTAssertEqual(playlists.playlist(id)?.songIDs, ["a", "b", "c", "a"])
        XCTAssertEqual(playlists.playlist(id)?.modified, later)

        // Same meaning as SwiftUI onMove: destination is an index before the move.
        playlists.move(from: [0], to: 3, in: id)
        XCTAssertEqual(playlists.playlist(id)?.songIDs, ["b", "c", "a", "a"])
        playlists.move(from: [3], to: 0, in: id)
        XCTAssertEqual(playlists.playlist(id)?.songIDs, ["a", "b", "c", "a"])
        playlists.move(from: [0, 2], to: 4, in: id)
        XCTAssertEqual(playlists.playlist(id)?.songIDs, ["b", "a", "a", "c"])
        playlists.move(from: [9], to: 0, in: id)
        XCTAssertEqual(playlists.playlist(id)?.songIDs, ["b", "a", "a", "c"])

        playlists.remove(at: [1, 3, 8], from: id)
        XCTAssertEqual(playlists.playlist(id)?.songIDs, ["b", "a"])
    }

    func testLibraryChangesUpdateEveryPlaylist() {
        var playlists = PlaylistCollection()
        let first = playlists.create(name: "One", songIDs: ["a", "b", "a"], now: start).id
        let second = playlists.create(name: "Two", songIDs: ["c"], now: start).id

        XCTAssertTrue(playlists.replaceSong("a", with: "kept", now: later))
        XCTAssertEqual(playlists.playlist(first)?.songIDs, ["kept", "b", "kept"])
        XCTAssertEqual(playlists.playlist(first)?.modified, later)
        XCTAssertEqual(playlists.playlist(second)?.modified, start)
        XCTAssertFalse(playlists.replaceSong("missing", with: "x"))

        XCTAssertTrue(playlists.removeSongs(["kept", "c"]))
        XCTAssertEqual(playlists.playlist(first)?.songIDs, ["b"])
        XCTAssertEqual(playlists.playlist(second)?.songIDs, [])
        XCTAssertFalse(playlists.removeSongs(["nothing"]))
    }

    func testSongsSkipEntriesMissingFromTheLibraryAndSurviveStorage() throws {
        let library = LocalLibraryIndex(tracks: [
            LocalTrack(id: "a", filename: "a.mp3", title: "Alpha", artist: "Band", album: "One"),
            LocalTrack(id: "b", filename: "b.mp3", title: "Beta", artist: "Band", album: "One"),
        ])
        var playlists = PlaylistCollection()
        let id = playlists.create(name: "Mix", songIDs: ["b", "gone", "a", "b"], now: start).id
        let restored = try JSONDecoder().decode(
            PlaylistCollection.self, from: JSONEncoder().encode(playlists))
        let playlist = try XCTUnwrap(restored.playlist(id))
        XCTAssertEqual(playlist, playlists.playlist(id))
        XCTAssertEqual(
            PlaylistCollection.songs(in: playlist, library: library).map(\.title), ["Beta", "Alpha", "Beta"])
        XCTAssertEqual(
            PlaylistCollection.entries(in: playlist, library: library).map(\.position), [0, 2, 3])
    }

    func testEditsOnVisibleEntriesSkipHiddenSongs() {
        let library = LocalLibraryIndex(tracks: [
            LocalTrack(id: "a", filename: "a.mp3", title: "A", artist: nil, album: nil),
            LocalTrack(id: "b", filename: "b.mp3", title: "B", artist: nil, album: nil),
            LocalTrack(id: "c", filename: "c.mp3", title: "C", artist: nil, album: nil),
        ])
        var playlists = PlaylistCollection()
        let id = playlists.create(name: "Mix", songIDs: ["a", "gone", "b", "c"]).id
        func visible() -> [PlaylistEntry] {
            PlaylistCollection.entries(in: playlists.playlist(id)!, library: library)
        }
        // Visible [A, B, C]: drag C to the top.
        var move = PlaylistCollection.storedMove(from: [2], to: 0, entries: visible(), storedCount: 4)
        playlists.move(from: move.offsets, to: move.destination, in: id)
        XCTAssertEqual(visible().map(\.song.id), ["c", "a", "b"])
        // Drag C to the end.
        move = PlaylistCollection.storedMove(from: [0], to: 3, entries: visible(), storedCount: 4)
        playlists.move(from: move.offsets, to: move.destination, in: id)
        XCTAssertEqual(visible().map(\.song.id), ["a", "b", "c"])
        // Delete visible B.
        playlists.remove(at: IndexSet(integer: visible()[1].position), from: id)
        XCTAssertEqual(visible().map(\.song.id), ["a", "c"])
        XCTAssertEqual(playlists.playlist(id)?.songIDs.contains("gone"), true)
    }
}
