import XCTest
@testable import HarmonyCore

final class LocalLibraryTests: XCTestCase {
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
