import XCTest
@testable import HarmonyCore

final class FLACArtworkTests: XCTestCase {
    func testExtractsPictureAndPrefersFrontCover() throws {
        let first = Data([1, 2, 3])
        let front = Data([4, 5, 6, 7])
        let data =
            Data("fLaC".utf8) + block(type: 0, data: Data(repeating: 0, count: 34))
            + block(type: 6, data: picture(type: 4, image: first))
            + block(type: 6, data: picture(type: 3, image: front), last: true)
        XCTAssertEqual(try extract(data), front)
    }

    func testFallsBackToAnotherPictureAndRejectsLinkedArtwork() throws {
        let image = Data([1, 2, 3])
        XCTAssertEqual(
            try extract(Data("fLaC".utf8) + block(type: 6, data: picture(type: 0, image: image), last: true)), image)
        XCTAssertNil(
            try extract(
                Data("fLaC".utf8) + block(type: 6, data: picture(type: 3, image: image, mime: "-->"), last: true)))
    }

    func testMalformedAndTruncatedBlocksReturnNoImage() throws {
        XCTAssertNil(try extract(Data("not a flac file".utf8)))
        let valid = Data("fLaC".utf8) + block(type: 6, data: picture(type: 3, image: Data([1, 2, 3])), last: true)
        for length in 4..<valid.count {
            XCTAssertNil(try extract(Data(valid.prefix(length))), "Truncated at \(length)")
        }
        XCTAssertNil(try extract(Data("fLaC".utf8) + block(type: 6, data: Data(repeating: 255, count: 20), last: true)))
    }

    func testRecoveredArtworkPersistsWithoutChangingTrackMetadata() throws {
        let track = LocalTrack(
            id: "existing", filename: "song.flac", title: "Title", artist: "Artist", album: "Album", track: 2)
        var library = LocalLibraryIndex(tracks: [track])
        library.setArtwork(for: track.id, filename: "existing.artwork")
        let restored = try JSONDecoder().decode(LocalLibraryIndex.self, from: JSONEncoder().encode(library))
        XCTAssertEqual(restored.tracks[0].artworkFilename, "existing.artwork")
        XCTAssertEqual(restored.songs[0].coverArt, track.id)
        XCTAssertEqual(restored.songs[0].title, "Title")
        XCTAssertEqual(restored.songs[0].track, 2)
        XCTAssertEqual(restored.albums[0].coverArt, track.id)
    }

    private func extract(_ data: Data) throws -> Data? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".flac")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)
        return try FLACArtwork.image(in: url)
    }
    private func number(_ value: Int) -> Data {
        Data([UInt8((value >> 24) & 255), UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255)])
    }
    private func picture(type: Int, image: Data, mime: String = "image/jpeg") -> Data {
        number(type) + number(mime.utf8.count) + Data(mime.utf8) + number(0)
            + number(2000) + number(2000) + number(24) + number(0) + number(image.count) + image
    }
    private func block(type: UInt8, data: Data, last: Bool = false) -> Data {
        Data([
            type | (last ? 128 : 0), UInt8((data.count >> 16) & 255), UInt8((data.count >> 8) & 255),
            UInt8(data.count & 255),
        ]) + data
    }
}
