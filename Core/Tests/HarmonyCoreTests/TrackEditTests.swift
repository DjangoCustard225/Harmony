import XCTest
@testable import HarmonyCore

final class TrackEditTests: XCTestCase {
    private func tagged() -> LocalTrack {
        var metadata = TrackMetadata()
        metadata.append("Song", for: "TITLE")
        metadata.append("Band", for: "ARTIST")
        metadata.append("Record", for: "ALBUM")
        metadata.append("Rock", for: "GENRE")
        metadata.append("3", for: "TRACKNUMBER")
        metadata.append("1999", for: "DATE")
        return LocalTrack(
            id: "t", filename: "t.flac", title: "Song", artist: "Band", album: "Record", track: 3,
            metadata: metadata, originalFilename: "01 Song.flac")
    }

    func testEditsOverrideTagsAndKeepOnlyChanges() throws {
        let track = tagged()
        XCTAssertNil(track.edits)
        XCTAssertEqual(track.tagFields.year, 1999)
        var fields = track.fields
        fields.title = " New title "
        fields.albumArtist = "Various"
        fields.genre = ""
        fields.track = nil
        fields.year = 2001
        let edited = track.editing(fields)

        let edits = try XCTUnwrap(edited.edits)
        XCTAssertEqual(edits.title, "New title")
        XCTAssertNil(edits.artist)
        XCTAssertEqual(edits.genre, "")
        XCTAssertEqual(edits.track, 0)
        XCTAssertEqual(edited.song.title, "New title")
        XCTAssertEqual(edited.song.artist, "Band")
        XCTAssertEqual(edited.song.albumArtist, "Various")
        XCTAssertNil(edited.song.track)
        XCTAssertNil(edited.genre)
        XCTAssertEqual(edited.year, 2001)
        XCTAssertEqual(edited.fields.title, "New title")
        XCTAssertEqual(edited.tagFields, track.tagFields)
        // Albums follow the edited album artist.
        XCTAssertNotEqual(edited.song.albumId, track.song.albumId)
        XCTAssertEqual(LocalLibraryIndex(tracks: [edited]).albums.first?.year, 2001)
    }

    func testRestoringTagValuesClearsEditsAndSurvivesStorage() throws {
        let track = tagged()
        var fields = track.fields
        fields.album = "Other"
        let edited = track.editing(fields)
        let restored = try JSONDecoder().decode(LocalTrack.self, from: JSONEncoder().encode(edited))
        XCTAssertEqual(restored.edits, edited.edits)
        XCTAssertEqual(restored.song.album, "Other")

        let reset = restored.editing(restored.tagFields)
        XCTAssertNil(reset.edits)
        XCTAssertEqual(reset.song.album, "Record")
    }

    func testOldLibraryEntriesLoadWithoutEdits() throws {
        let json = #"{"song":{"id":"a","title":"A"},"filename":"a.mp3","added":0}"#
        let track = try JSONDecoder().decode(LocalTrack.self, from: Data(json.utf8))
        XCTAssertNil(track.edits)
        XCTAssertEqual(track.fields.title, "A")
    }
}
