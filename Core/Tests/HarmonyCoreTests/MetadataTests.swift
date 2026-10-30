import XCTest
@testable import HarmonyCore

final class MetadataTests: XCTestCase {
    func testVorbisTagsPreserveUnicodeRepeatsAliasesAndEquals() throws {
        let tags = [
            "title=Été", "artist=Lead", "ARTIST=Guest", "album_artist=Band", "album=Summer", "TRACKNUMBER=2/10",
            "DISCNUMBER=1/2", "DATE=2018-12-07", "GENRE=Pop", "COMPOSER=One", "COMPOSER=Two", "CUSTOM=a=b",
            "LYRICS=[00:01.25]Example",
        ]
        let metadata = try XCTUnwrap(parse(flac(tags)))
        XCTAssertEqual(metadata.title, "Été")
        XCTAssertEqual(metadata.artist, "Lead; Guest")
        XCTAssertEqual(metadata.albumArtist, "Band")
        XCTAssertEqual(
            LocalTrack(filename: "test.flac", title: "Example", artist: nil, album: nil, albumArtist: "Band").song
                .artistName, "Band")
        XCTAssertEqual(metadata.album, "Summer")
        XCTAssertEqual(metadata.track, 2)
        XCTAssertEqual(metadata.disc, 1)
        XCTAssertEqual(metadata.year, 2018)
        XCTAssertEqual(metadata.genre, "Pop")
        XCTAssertEqual(metadata.values("COMPOSER"), ["One", "Two"])
        XCTAssertEqual(metadata.text("CUSTOM"), "a=b")
        XCTAssertEqual(metadata.lyrics, "[00:01.25]Example")
    }
    func testTruncatedCommentsNeverInventTags() throws {
        let data = flac(["TITLE=Example", "ARTIST=Test"])
        for length in 4..<data.count {
            let metadata = try parse(Data(data.prefix(length)))
            XCTAssertTrue(metadata?.tags.isEmpty ?? true)
        }
        XCTAssertNil(try parse(Data("not FLAC".utf8)))
        let malicious = Data("fLaC".utf8) + block(type: 4, payload: Data(repeating: 255, count: 8))
        XCTAssertTrue(try XCTUnwrap(parse(malicious)).tags.isEmpty)
    }
    func testLRCMultipleTimestampsOffsetsAndPlainText() {
        let text = "[ti:Example]\n[ar:Test]\n[offset:200]\n[00:02.50][00:01.25]Example\n[01:03.000]Next"
        let lyrics = EmbeddedLyrics.parse(text)
        XCTAssertTrue(lyrics.synced)
        XCTAssertEqual(lyrics.line.map(\.start), [1250, 2500, 63000])
        XCTAssertEqual(lyrics.line.map(\.value), ["Example", "Example", "Next"])
        XCTAssertEqual(lyrics.offset, -200)
        XCTAssertEqual(lyrics.seekTime(for: 0), 1.45)
        XCTAssertNil(lyrics.activeLineIndex(at: 1.4))
        XCTAssertEqual(lyrics.activeLineIndex(at: 1.45), 0)
        let plain = EmbeddedLyrics.parse("First\r\n\r\nSecond")
        XCTAssertFalse(plain.synced)
        XCTAssertEqual(plain.line.map(\.value), ["First", "", "Second"])
        XCTAssertFalse(EmbeddedLyrics.parse("[00:bad]Text").synced)
        XCTAssertFalse(EmbeddedLyrics.parse("[00:99]Text").synced)
    }
    func testLegacyLibraryDecodesAndMetadataRefreshKeepsIdentity() throws {
        let json =
            #"{"tracks":[{"song":{"id":"existing","title":"filename","artist":"Unknown artist","album":"Unknown album"},"filename":"existing.flac","added":1234}]}"#
        var library = try JSONDecoder().decode(LocalLibraryIndex.self, from: Data(json.utf8))
        let old = try XCTUnwrap(library.tracks.first)
        XCTAssertNil(old.metadataVersion)
        var metadata = TrackMetadata(tags: [
            "TITLE": ["Example"], "ARTIST": ["Lead; Guest"], "ALBUMARTIST": ["Band"], "ALBUM": ["Album"],
            "DATE": ["2020"], "GENRE": ["Pop"],
        ])
        metadata.sampleRate = 44100
        let refreshed = LocalTrack(
            id: old.id, filename: old.filename, title: metadata.title!, artist: metadata.artist,
            album: metadata.album, albumArtist: metadata.albumArtist, lyrics: "[00:01.00]Example",
            added: old.added, metadata: metadata, metadataVersion: 1)
        library.replace(refreshed)
        let restored = try JSONDecoder().decode(LocalLibraryIndex.self, from: JSONEncoder().encode(library))
        XCTAssertEqual(restored.tracks[0].id, old.id)
        XCTAssertEqual(restored.tracks[0].filename, old.filename)
        XCTAssertEqual(restored.tracks[0].added, old.added)
        XCTAssertEqual(restored.tracks[0].metadata?.sampleRate, 44100)
        XCTAssertEqual(restored.songs[0].artistName, "Lead; Guest")
        XCTAssertEqual(restored.albums[0].artistName, "Band")
        XCTAssertEqual(restored.albums[0].year, 2020)
        XCTAssertEqual(restored.albums[0].genre, "Pop")
        XCTAssertEqual(restored.artists[0].name, "Band")
        XCTAssertEqual(restored.search("Band").songs.count, 1)
    }
    func testRefreshingMetadataPreservesShuffledQueueAndCurrentTrack() {
        let old = (1...3).map {
            LocalTrack(id: String($0), filename: "\($0).flac", title: "Old", artist: nil, album: nil).song
        }
        let updated = (1...3).map {
            LocalTrack(id: String($0), filename: "\($0).flac", title: "New \($0)", artist: "Artist", album: "Album")
                .song
        }
        var queue = PlaybackQueue()
        queue.replace(old, startingAt: 1, shuffle: true)
        queue.repeatMode = .all
        queue.append(old[1], next: true)
        let order = queue.songs.map(\.id)
        queue.refreshMetadata(updated)
        XCTAssertEqual(queue.songs.map(\.id), order)
        XCTAssertEqual(queue.current?.id, "2")
        XCTAssertEqual(queue.current?.title, "New 2")
        XCTAssertTrue(queue.shuffled)
        XCTAssertEqual(queue.repeatMode, .all)
        queue.toggleShuffle()
        XCTAssertTrue(queue.songs.allSatisfy { $0.title.hasPrefix("New ") })
    }
    func testRealFLACMatchesIndependentMetadataReader() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let source = environment["HARMONY_METADATA_FIXTURE"],
            let expected = environment["HARMONY_METADATA_EXPECTED"]
        else {
            throw XCTSkip("Set fixture and oracle paths to validate a real FLAC")
        }
        let actual = try XCTUnwrap(FLACMetadata.read(from: URL(fileURLWithPath: source)))
        let oracle = try JSONDecoder().decode(
            TrackMetadata.self, from: Data(contentsOf: URL(fileURLWithPath: expected)))
        XCTAssertEqual(actual.tags, oracle.tags)
        XCTAssertEqual(actual.sampleRate, oracle.sampleRate)
        XCTAssertEqual(actual.channels, oracle.channels)
        XCTAssertEqual(actual.bitsPerSample, oracle.bitsPerSample)
        XCTAssertEqual(try XCTUnwrap(actual.duration), try XCTUnwrap(oracle.duration), accuracy: 0.000001)
        let lyrics = EmbeddedLyrics.parse(try XCTUnwrap(actual.lyrics))
        XCTAssertTrue(lyrics.synced)
        XCTAssertEqual(lyrics.line.first?.start, 7120)
        XCTAssertEqual(lyrics.line.last?.start, 166290)
        XCTAssertTrue(lyrics.line.allSatisfy { !$0.value.contains("[00:") })
    }
    private func parse(_ data: Data) throws -> TrackMetadata? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)
        return try FLACMetadata.read(from: url)
    }
    private func little(_ value: Int) -> Data {
        Data((0..<4).map { UInt8((value >> ($0 * 8)) & 255) })
    }
    private func flac(_ tags: [String]) -> Data {
        var comments = little(4) + Data("Test".utf8) + little(tags.count)
        for tag in tags { comments += little(tag.utf8.count) + Data(tag.utf8) }
        return Data("fLaC".utf8) + block(type: 4, payload: comments)
    }
    private func block(type: UInt8, payload: Data) -> Data {
        Data([
            type | 128, UInt8((payload.count >> 16) & 255), UInt8((payload.count >> 8) & 255),
            UInt8(payload.count & 255),
        ]) + payload
    }
}
