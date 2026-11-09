import XCTest
@testable import HarmonyCore

final class LocalLibraryTests: XCTestCase {
    #if canImport(CryptoKit)
        func testFingerprintReadsFullContentAndRechecksChangedFiles() throws {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let a = folder.appendingPathComponent("first.mp3")
            let b = folder.appendingPathComponent("renamed.flac")
            try Data("abc".utf8).write(to: a)
            try Data("abc".utf8).write(to: b)
            let first = try FileFingerprint.read(a)
            let second = try FileFingerprint.read(b)
            XCTAssertEqual(first.sha256, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
            XCTAssertEqual(first.sha256, second.sha256)
            try Data("different".utf8).write(to: a)
            XCTAssertNotEqual(try FileFingerprint.read(a, cached: first).sha256, first.sha256)
            try FileManager.default.removeItem(at: a)
            XCTAssertThrowsError(try FileFingerprint.read(a, cached: first))
        }
    #endif
    func testFingerprintsSurviveStorageAndGroupOnlyMatchingContents() throws {
        let stamp = Date(timeIntervalSince1970: 100)
        let matching = FileFingerprint(sha256: "same", size: 10, modified: stamp)
        let otherSize = FileFingerprint(sha256: "same", size: 11, modified: stamp)
        let a = LocalTrack(id: "a", filename: "a.mp3", title: "Song", artist: "Band", album: "One")
        let b = LocalTrack(id: "b", filename: "b.mp3", title: "Song", artist: "Band", album: "One")
        let c = LocalTrack(id: "c", filename: "c.mp3", title: "Song", artist: "Band", album: "One")
        var library = LocalLibraryIndex(tracks: [a, b, c])
        library.setFingerprint(matching, for: "a")
        library.setFingerprint(matching, for: "b")
        library.setFingerprint(otherSize, for: "c")
        let restored = try JSONDecoder().decode(LocalLibraryIndex.self, from: JSONEncoder().encode(library))
        XCTAssertEqual(restored.duplicateGroups.map { $0.map(\.id) }, [["a", "b"]])
        XCTAssertEqual(restored.tracks.first?.fingerprint, matching)
        library.setFingerprint(nil, for: "b")
        XCTAssertTrue(library.duplicateGroups.isEmpty)
    }
    func testLegacyManifestWithoutFingerprintDecodes() throws {
        let track = LocalTrack(filename: "a.flac", title: "Song", artist: nil, album: nil)
        let data = try JSONEncoder().encode(LocalLibraryIndex(tracks: [track]))
        var manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var tracks = try XCTUnwrap(manifest["tracks"] as? [[String: Any]])
        tracks[0].removeValue(forKey: "fingerprint")
        manifest["tracks"] = tracks
        let restored = try JSONDecoder().decode(
            LocalLibraryIndex.self, from: JSONSerialization.data(withJSONObject: manifest))
        XCTAssertNil(restored.tracks[0].fingerprint)
        XCTAssertTrue(restored.duplicateGroups.isEmpty)
    }
    func testAlbumsUseAlbumArtistAndDiscTrackOrder() throws {
        let tracks = [
            LocalTrack(
                id: "3", filename: "3.flac", title: "Finale", artist: "Guest", album: "Live", albumArtist: "Band",
                duration: 80, track: 1, disc: 2),
            LocalTrack(
                id: "2", filename: "2.flac", title: "Middle", artist: "Band", album: "Live", duration: 60, track: 2,
                disc: 1, artworkFilename: "2.art"),
            LocalTrack(
                id: "1", filename: "1.flac", title: "Opening", artist: "Band", album: "Live", duration: 40, track: 1,
                disc: 1),
            LocalTrack(id: "other", filename: "other.flac", title: "Other", artist: "Other band", album: "Live"),
        ]
        let library = LocalLibraryIndex(tracks: tracks)
        XCTAssertEqual(library.albums.count, 2)
        let album = try XCTUnwrap(library.albums.first { $0.artistName == "Band" })
        XCTAssertEqual(album.songs.map(\.id), ["1", "2", "3"])
        XCTAssertEqual(album.duration, 180)
        XCTAssertEqual(album.songCount, 3)
        XCTAssertEqual(album.coverArt, "2")
        XCTAssertEqual(library.artists.first { $0.name == "Band" }?.albums.map(\.id), [album.id])
    }
    func testMissingMetadataHasUsefulFallbacks() {
        let track = LocalTrack(filename: "a.wav", title: "  ", artist: nil, album: " ")
        XCTAssertEqual(track.song.title, "Untitled")
        XCTAssertEqual(track.song.artistName, "Unknown artist")
        XCTAssertEqual(track.song.album, "Unknown album")
        XCTAssertEqual(track.song.suffix, "wav")
    }
    func testGroupingIgnoresCaseAndDoesNotCollideAcrossNameBoundaries() {
        let tracks = [
            LocalTrack(filename: "a", title: "A", artist: "Band", album: "Live"),
            LocalTrack(filename: "b", title: "B", artist: "band", album: "live"),
            LocalTrack(filename: "c", title: "C", artist: "ab", album: "c"),
            LocalTrack(filename: "d", title: "D", artist: "a", album: "bc"),
        ]
        XCTAssertEqual(LocalLibraryIndex(tracks: tracks).albums.count, 3)
    }
    func testSearchMatchesTitlesArtistsAndAlbumsIgnoringCaseAndAccents() {
        let library = LocalLibraryIndex(tracks: [
            LocalTrack(id: "1", filename: "a.mp3", title: "Été", artist: "Band", album: "Summer")
        ])
        XCTAssertEqual(library.search("ete").songs.map(\.id), ["1"])
        XCTAssertEqual(library.search("  BAND ").songs.count, 1)
        XCTAssertEqual(library.search("summer").albums.count, 1)
        XCTAssertEqual(library.search("Band").artists.count, 1)
        XCTAssertTrue(library.search(" ").isEmpty)
        XCTAssertTrue(library.search("winter").isEmpty)
    }
    func testManifestRoundTripPreservesFilesArtworkAndLyrics() throws {
        let track = LocalTrack(
            id: "1", filename: "1.m4a", title: "Title", artist: "Artist", album: "Album", artworkFilename: "1.art",
            lyrics: "First\nSecond")
        let original = LocalLibraryIndex(tracks: [track])
        let restored = try JSONDecoder().decode(LocalLibraryIndex.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(restored.songs, original.songs)
        XCTAssertEqual(restored.tracks[0].filename, "1.m4a")
        XCTAssertEqual(restored.tracks[0].artworkFilename, "1.art")
        XCTAssertEqual(restored.tracks[0].lyrics, "First\nSecond")
        XCTAssertEqual(restored.tracks[0].added, track.added)
    }
    func testRemovalUpdatesAlbumAndArtistIndexes() {
        let a = LocalTrack(id: "a", filename: "a", title: "A", artist: "Band", album: "Album")
        let b = LocalTrack(id: "b", filename: "b", title: "B", artist: "Band", album: "Album")
        var library = LocalLibraryIndex(tracks: [a, b])
        library.remove("a")
        XCTAssertEqual(library.albums[0].songCount, 1)
        XCTAssertEqual(library.songs.map(\.id), ["b"])
        library.remove("b")
        XCTAssertTrue(library.albums.isEmpty)
        XCTAssertTrue(library.artists.isEmpty)
    }
}
