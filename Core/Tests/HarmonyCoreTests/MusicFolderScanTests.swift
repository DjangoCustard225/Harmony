import XCTest
@testable import HarmonyCore

final class MusicFolderScanTests: XCTestCase {
    func testFindsMusicRecursivelyAndSkipsUnrelatedFiles() throws {
        try withFolder { root in
            let disc = root.appendingPathComponent("Album/Disc 2", isDirectory: true)
            try FileManager.default.createDirectory(at: disc, withIntermediateDirectories: true)
            try Data().write(to: root.appendingPathComponent("Song.MP3"))
            try Data().write(to: disc.appendingPathComponent("Track.FLAC"))
            try Data().write(to: disc.appendingPathComponent("Track 2.m4a"))
            try Data().write(to: root.appendingPathComponent("cover.jpg"))
            try Data().write(to: root.appendingPathComponent("notes.txt"))
            try Data().write(to: root.appendingPathComponent("Library.json"))
            let scan = try MusicFolderScan.scan(root)
            XCTAssertEqual(Set(scan.files.map(\.lastPathComponent)), ["Song.MP3", "Track.FLAC", "Track 2.m4a"])
            XCTAssertTrue(scan.warnings.isEmpty)
        }
    }
    func testSkipsHiddenFilesDirectoriesAndSymbolicLinks() throws {
        try withFolder { root in
            let hidden = root.appendingPathComponent(".hidden", isDirectory: true)
            try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
            try Data().write(to: hidden.appendingPathComponent("Secret.mp3"))
            try Data().write(to: root.appendingPathComponent(".hidden.flac"))
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("Not a song.flac"), withIntermediateDirectories: true)
            let actual = root.appendingPathComponent("Track.wav")
            try Data().write(to: actual)
            try FileManager.default.createSymbolicLink(
                at: root.appendingPathComponent("Link.wav"), withDestinationURL: actual)
            try FileManager.default.createSymbolicLink(
                at: root.appendingPathComponent("Loop"), withDestinationURL: root)
            let scan = try MusicFolderScan.scan(root)
            XCTAssertEqual(scan.files.map(\.lastPathComponent), ["Track.wav"])
        }
    }
    func testEmptyMissingAndNonDirectorySelections() throws {
        try withFolder { root in
            XCTAssertTrue(try MusicFolderScan.scan(root).files.isEmpty)
            XCTAssertThrowsError(try MusicFolderScan.scan(root.appendingPathComponent("missing")))
            let file = root.appendingPathComponent("song.mp3")
            try Data().write(to: file)
            XCTAssertThrowsError(try MusicFolderScan.scan(file))
        }
    }
    func testDiscoveryDoesNotChangeSourceFiles() throws {
        try withFolder { root in
            let file = root.appendingPathComponent("Track.flac")
            let content = Data([1, 2, 3, 4])
            try content.write(to: file)
            _ = try MusicFolderScan.scan(root)
            XCTAssertEqual(try Data(contentsOf: file), content)
        }
    }
    func testRealAlbumFolderIncludesSelectedTrack() throws {
        guard let path = ProcessInfo.processInfo.environment["HARMONY_METADATA_FIXTURE"] else {
            throw XCTSkip("Set HARMONY_METADATA_FIXTURE to test a real album folder")
        }
        let track = URL(fileURLWithPath: path)
        let scan = try MusicFolderScan.scan(track.deletingLastPathComponent())
        XCTAssertTrue(scan.files.contains(track))
        XCTAssertTrue(scan.warnings.isEmpty)
    }
    private func withFolder(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }
}
