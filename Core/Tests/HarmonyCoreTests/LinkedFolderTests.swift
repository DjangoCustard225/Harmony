import XCTest
@testable import HarmonyCore

final class LinkedFolderTests: XCTestCase {
    private func print(_ hash: String) -> FileFingerprint {
        FileFingerprint(sha256: hash, size: 10, modified: Date(timeIntervalSince1970: 0))
    }
    private func track(_ id: String, _ path: String, folder: String?, hash: String = "") -> LocalTrack {
        LocalTrack(
            id: id, filename: path, title: id, artist: nil, album: nil, fingerprint: print(hash.isEmpty ? id : hash),
            folderID: folder)
    }

    func testChangesFindNewAndMissingFilesInOneFolderOnly() {
        let folder = LinkedFolder(id: "f", name: "Music", bookmark: Data(), hidden: ["Skip/x.mp3"])
        let index = LocalLibraryIndex(
            tracks: [
                track("a", "A/a.flac", folder: "f"),
                track("b", "B/b.flac", folder: "f"),
                track("own", "c.flac", folder: nil),
                track("other", "c.flac", folder: "g"),
            ],
            folders: [folder])
        let changes = LinkedFolderChanges(
            folderID: "f", scanned: ["A/a.flac", "c.flac", "Skip/x.mp3", "c.flac", "New/d.mp3"], index: index)
        XCTAssertEqual(changes.added, ["c.flac", "New/d.mp3"])
        XCTAssertEqual(changes.missing.map(\.id), ["b"])
    }

    func testMovesMatchMissingSongsByContent() {
        let missing = [track("b", "B/b.flac", folder: "f", hash: "beta"), track("z", "z.flac", folder: "f", hash: "z")]
        XCTAssertEqual(LinkedFolderChanges.moveSource(for: print("beta"), among: missing)?.id, "b")
        XCTAssertNil(LinkedFolderChanges.moveSource(for: print("new"), among: missing))
        let moved = missing[0].moved(to: "Renamed/b.flac")
        XCTAssertEqual(moved.id, "b")
        XCTAssertEqual(moved.filename, "Renamed/b.flac")
        XCTAssertEqual(moved.folderID, "f")
    }

    func testHideAndUnlinkLeaveOtherSongsAlone() {
        var index = LocalLibraryIndex(
            tracks: [
                track("a", "a.flac", folder: "f"), track("b", "b.flac", folder: "f"), track("c", "c.flac", folder: nil),
            ],
            folders: [LinkedFolder(id: "f", name: "Music", bookmark: Data())])
        index.hide("a")
        index.hide("c")  // Songs in Harmony's own folder aren't hidden this way.
        XCTAssertEqual(index.tracks.map(\.id), ["b", "c"])
        XCTAssertEqual(index.folder("f")?.hidden, ["a.flac"])
        XCTAssertEqual(LinkedFolderChanges(folderID: "f", scanned: ["a.flac", "b.flac"], index: index).added, [])

        XCTAssertEqual(index.removeFolder("f").map(\.id), ["b"])
        XCTAssertEqual(index.tracks.map(\.id), ["c"])
        XCTAssertTrue(index.folders.isEmpty)
    }

    func testStorageRoundTripsAndOldLibrariesLoad() throws {
        let folder = LinkedFolder(id: "f", name: "iCloud Music", bookmark: Data([1, 2]), hidden: ["x.mp3"])
        let index = LocalLibraryIndex(tracks: [track("a", "Sub/a.flac", folder: "f")], folders: [folder])
        let restored = try JSONDecoder().decode(LocalLibraryIndex.self, from: JSONEncoder().encode(index))
        XCTAssertEqual(restored.folders, [folder])
        XCTAssertEqual(restored.tracks.first?.folderID, "f")
        XCTAssertEqual(restored.tracks.first?.filename, "Sub/a.flac")

        let old = #"{"tracks":[{"song":{"id":"a","title":"A"},"filename":"a.mp3","added":0}]}"#
        let legacy = try JSONDecoder().decode(LocalLibraryIndex.self, from: Data(old.utf8))
        XCTAssertTrue(legacy.folders.isEmpty)
        XCTAssertNil(legacy.tracks.first?.folderID)
        let oldFolder = #"{"id":"f","name":"M","bookmark":"AQI=","added":0}"#
        XCTAssertEqual(try JSONDecoder().decode(LinkedFolder.self, from: Data(oldFolder.utf8)).hidden, [])
    }

    func testScanReportsICloudPlaceholdersAndSkipsHiddenItems() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("Album/.hidden"), withIntermediateDirectories: true)
        for name in [
            "Album/a.flac", "Album/.b.mp3.icloud", "Album/.notes.txt.icloud", "Album/.hidden/c.flac", ".DS_Store",
        ] {
            fm.createFile(atPath: root.appendingPathComponent(name).path, contents: Data())
        }
        let scan = try MusicFolderScan.scan(root)
        XCTAssertEqual(scan.files.compactMap { MusicFolderScan.relativePath(of: $0, in: root) }, ["Album/a.flac"])
        // Placeholders stand for files that don't exist yet, so compare names rather than resolved paths.
        XCTAssertEqual(
            scan.placeholders.map { "\($0.deletingLastPathComponent().lastPathComponent)/\($0.lastPathComponent)" },
            ["Album/b.mp3"])
    }
}
