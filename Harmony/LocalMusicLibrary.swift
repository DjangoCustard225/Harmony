import AVFoundation
import CryptoKit
import UIKit
import HarmonyCore

enum MusicImportResult { case added, duplicate }

struct MetadataRefreshResult {
    var changed = false
    var failures: [String] = []
}

struct FolderSyncResult {
    var added = 0
    var moved = 0
    var duplicates = 0
    /// iCloud songs asked to download; they're added by a later scan.
    var downloading = 0
    var removed: [LocalTrack] = []
    var failures: [String] = []
}

/// Owns imported copies, and indexes linked folders where they are. Imported songs never depend on
/// a provider URL; linked songs need their folder, which is reopened from a bookmark at launch.
@MainActor
final class LocalMusicLibrary {
    private let root: URL
    /// Linked folders by ID, with security-scoped access held for as long as the app runs.
    private var folderURLs: [String: URL] = [:]
    private(set) var index = LocalLibraryIndex() {
        didSet { albumCache = nil }
    }
    private var albumCache: [Album]?
    /// Artwork content hashes by song ID, so identical covers saved per song compare equal.
    private var artworkKeys: [String: String] = [:]
    /// Grouping the library into albums sorts every track, so it's done once per change.
    var albums: [Album] {
        if let albumCache { return albumCache }
        let value = index.albums
        albumCache = value
        return value
    }
    init() throws {
        root = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        .appendingPathComponent("Music", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let manifest = root.appendingPathComponent("Library.json")
        if FileManager.default.fileExists(atPath: manifest.path) {
            index = try JSONDecoder().decode(LocalLibraryIndex.self, from: Data(contentsOf: manifest))
        }
        openLinkedFolders()
    }
    private func save(_ value: LocalLibraryIndex) throws {
        try JSONEncoder().encode(value).write(to: root.appendingPathComponent("Library.json"), options: .atomic)
        index = value
    }

    // MARK: Linked folders

    func isAvailable(_ folderID: String) -> Bool { folderURLs[folderID] != nil }

    /// Where a song's file lives, or nil when its linked folder can't be opened.
    func url(for track: LocalTrack) -> URL? {
        guard let folderID = track.folderID else { return root.appendingPathComponent(track.filename) }
        return folderURLs[folderID]?.appendingPathComponent(track.filename)
    }

    /// "Harmony" for imported copies, or the linked folder and path.
    func location(of track: LocalTrack) -> String {
        guard let folderID = track.folderID else { return "Harmony" }
        return "\(index.folder(folderID)?.name ?? "Linked folder")/\(track.filename)"
    }

    private func openLinkedFolders() {
        var updated = index
        for folder in index.folders {
            var stale = false
            guard
                let url = try? URL(
                    resolvingBookmarkData: folder.bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
            else { continue }
            let access = url.startAccessingSecurityScopedResource()
            guard access || FileManager.default.isReadableFile(atPath: url.path) else { continue }
            folderURLs[folder.id] = url
            // A renamed or moved folder still resolves; refresh its bookmark and name.
            if stale || folder.name != url.lastPathComponent, let bookmark = try? url.bookmarkData() {
                var renewed = folder
                renewed.bookmark = bookmark
                renewed.name = url.lastPathComponent
                updated.updateFolder(renewed)
            }
        }
        if updated.folders != index.folders { try? save(updated) }
    }

    /// Links a folder the user picked. Picking an already linked folder, or reconnecting one with
    /// `replacing`, keeps its songs and playlists.
    func link(_ url: URL, replacing id: String? = nil) throws -> LinkedFolder {
        if url.standardizedFileURL.resolvingSymlinksInPath() == root.standardizedFileURL.resolvingSymlinksInPath()
            || MusicFolderScan.relativePath(of: url, in: root) != nil
        {
            throw LocalLibraryError.ownFolder
        }
        let access = url.startAccessingSecurityScopedResource()
        do {
            let bookmark = try url.bookmarkData()
            let target = url.standardizedFileURL.resolvingSymlinksInPath()
            let existing =
                id.flatMap(index.folder)
                ?? index.folders.first { folder in
                    folderURLs[folder.id].map { $0.standardizedFileURL.resolvingSymlinksInPath() == target } ?? false
                }
            var folder = existing ?? LinkedFolder(name: url.lastPathComponent, bookmark: bookmark)
            folder.bookmark = bookmark
            folder.name = url.lastPathComponent
            var updated = index
            updated.addFolder(folder)
            try save(updated)
            if let previous = folderURLs[folder.id], previous != url { previous.stopAccessingSecurityScopedResource() }
            folderURLs[folder.id] = url
            return folder
        } catch {
            if access { url.stopAccessingSecurityScopedResource() }
            throw error
        }
    }

    /// Unlinks a folder and forgets its songs. The folder and its files aren't touched.
    func unlink(_ id: String) throws -> [LocalTrack] {
        var updated = index
        let removed = updated.removeFolder(id)
        try save(updated)
        folderURLs.removeValue(forKey: id)?.stopAccessingSecurityScopedResource()
        deleteArtwork(of: removed)
        return removed
    }

    /// Lets songs removed from Harmony come back on the next scan.
    func showHidden(in id: String) throws {
        guard var folder = index.folder(id) else { return }
        folder.hidden = []
        var updated = index
        updated.updateFolder(folder)
        try save(updated)
    }

    /// Brings the index in line with a linked folder: adds new files, follows moved or renamed ones
    /// (matched by content, so playlists keep them), and drops songs whose files are gone.
    func syncFolder(_ id: String, progress: (String) -> Void) async throws -> FolderSyncResult {
        guard let folder = index.folder(id) else { return FolderSyncResult() }
        guard let directory = folderURLs[id] else { throw LocalLibraryError.folderUnavailable(folder.name) }
        progress("Scanning \(folder.name)…")
        let scan = try await Task.detached(priority: .userInitiated) {
            var coordinationError: NSError?
            var scanResult: Result<MusicFolderScan, Error>?
            NSFileCoordinator().coordinate(readingItemAt: directory, options: [], error: &coordinationError) { url in
                scanResult = Result { try MusicFolderScan.scan(url) }
            }
            if let coordinationError { throw coordinationError }
            guard let scanResult else { throw CocoaError(.fileReadUnknown) }
            return try scanResult.get()
        }.value
        var result = FolderSyncResult()
        result.failures = scan.warnings
        for placeholder in scan.placeholders {
            if (try? FileManager.default.startDownloadingUbiquitousItem(at: placeholder)) != nil {
                result.downloading += 1
            }
        }
        let paths = scan.files.compactMap { MusicFolderScan.relativePath(of: $0, in: directory) }
        let changes = LinkedFolderChanges(folderID: id, scanned: paths, index: index)
        var missing = changes.missing
        for (position, path) in changes.added.enumerated() {
            progress("Adding \(position + 1) of \(changes.added.count) from \(folder.name)…")
            let file = directory.appendingPathComponent(path)
            do {
                let fingerprint = try await Self.fingerprint(file)
                if let source = LinkedFolderChanges.moveSource(for: fingerprint, among: missing) {
                    missing.removeAll { $0.id == source.id }
                    var updated = index
                    updated.replace(source.moved(to: path))
                    try save(updated)
                    result.moved += 1
                    continue
                }
                switch try await addTrack(
                    id: UUID().uuidString, file: file, filename: path, originalFilename: file.lastPathComponent,
                    fingerprint: fingerprint, folderID: id)
                {
                case .added: result.added += 1
                case .duplicate: result.duplicates += 1
                }
            } catch {
                result.failures.append("\(path): \(error.localizedDescription)")
            }
        }
        // A folder that reads as empty while it still has songs is more likely unreachable than
        // emptied; keep the songs rather than wiping them.
        if paths.isEmpty && !index.tracks(inFolder: id).isEmpty {
            result.failures.insert(
                "\(folder.name) looks empty, so no songs were removed. Unlink it in Settings to remove them.", at: 0)
            missing = []
        }
        var updated = index
        for track in missing { updated.remove(track.id) }
        if var scanned = updated.folder(id) {
            scanned.lastScan = Date()
            updated.updateFolder(scanned)
        }
        try save(updated)
        deleteArtwork(of: missing)
        result.removed = missing
        return result
    }

    private func deleteArtwork(of tracks: [LocalTrack]) {
        for artwork in tracks.compactMap(\.artworkFilename) {
            try? FileManager.default.removeItem(at: root.appendingPathComponent(artwork))
        }
    }

    /// Copies a file into Harmony's folder. App-owned temporary copies (from the Files picker or
    /// another app's "Open in") are moved instead, and are never left behind.
    func importFile(_ source: URL) async throws -> MusicImportResult {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        // A file opened from Harmony's own folder in Files is already in place.
        if let filename = MusicFolderScan.relativePath(of: source, in: root) {
            if index.tracks.contains(where: { $0.folderID == nil && $0.filename == filename }) { return .duplicate }
            return try await addExistingFile(source)
        }
        let temporary = Self.isAppOwnedTemporary(source)
        defer { if temporary { try? FileManager.default.removeItem(at: source) } }
        let id = UUID().uuidString
        let filename = id + "." + source.pathExtension.lowercased()
        let destination = root.appendingPathComponent(filename)
        var committed = false
        defer { if !committed { try? FileManager.default.removeItem(at: destination) } }
        // File providers may need time to materialize cloud files; keep that work off the UI thread.
        try await Task.detached(priority: .userInitiated) {
            if temporary, (try? FileManager.default.moveItem(at: source, to: destination)) != nil { return }
            var coordinationError: NSError?
            var copyError: Error?
            NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { url in
                do { try FileManager.default.copyItem(at: url, to: destination) } catch { copyError = error }
            }
            if let error = coordinationError { throw error }
            if let error = copyError { throw error }
        }.value
        let result = try await addTrack(
            id: id, file: destination, filename: filename, originalFilename: source.lastPathComponent)
        committed = result == .added
        return result
    }

    /// Indexes an audio file the user placed in Harmony's folder, where it is, without copying it.
    /// A byte-identical copy of a song already in the library is deleted: its contents are kept.
    func addExistingFile(_ url: URL) async throws -> MusicImportResult {
        guard let filename = MusicFolderScan.relativePath(of: url, in: root),
            !index.tracks.contains(where: { $0.folderID == nil && $0.filename == filename })
        else { throw LocalLibraryError.unsupported(url.lastPathComponent) }
        let fingerprint = try await Self.fingerprint(url)
        if let original = track(matching: fingerprint) {
            // Only delete when the kept copy is Harmony's own and still on disk. A copy that only
            // exists in a linked folder would be lost if that folder were unlinked.
            if original.folderID == nil,
                FileManager.default.fileExists(atPath: root.appendingPathComponent(original.filename).path)
            {
                try FileManager.default.removeItem(at: url)
            }
            return .duplicate
        }
        return try await addTrack(
            id: UUID().uuidString, file: url, filename: filename, originalFilename: url.lastPathComponent,
            fingerprint: fingerprint)
    }

    private func addTrack(
        id: String, file: URL, filename: String, originalFilename: String, fingerprint known: FileFingerprint? = nil,
        folderID: String? = nil
    ) async throws -> MusicImportResult {
        let artworkName = id + ".artwork"
        var committed = false
        defer { if !committed { try? FileManager.default.removeItem(at: root.appendingPathComponent(artworkName)) } }
        let fingerprint: FileFingerprint
        if let known { fingerprint = known } else { fingerprint = try await Self.fingerprint(file) }
        if track(matching: fingerprint) != nil { return .duplicate }
        let asset = AVURLAsset(url: file)
        guard try await asset.load(.isPlayable), !(try await asset.loadTracks(withMediaType: .audio)).isEmpty else {
            throw LocalLibraryError.unsupported(originalFilename)
        }
        let metadata = try await LocalMetadataReader.read(file)
        var artworkFilename: String?
        if let data = await embeddedArtwork(in: file) {
            try data.write(to: root.appendingPathComponent(artworkName), options: .atomic)
            artworkFilename = artworkName
        }
        let entry = LocalTrack(
            id: id, filename: filename, title: metadata.title ?? Self.title(fromFilename: originalFilename),
            artist: metadata.artist, album: metadata.album, albumArtist: metadata.albumArtist,
            duration: Self.seconds(metadata.duration), track: metadata.track, disc: metadata.disc,
            artworkFilename: artworkFilename, lyrics: metadata.lyrics, metadata: metadata,
            originalFilename: originalFilename, metadataVersion: LocalMetadataReader.version,
            fingerprint: fingerprint, folderID: folderID
        )
        var updated = index
        updated.append(entry)
        try save(updated)
        committed = true
        return .added
    }

    private func track(matching fingerprint: FileFingerprint) -> LocalTrack? {
        index.tracks.first { $0.fingerprint?.size == fingerprint.size && $0.fingerprint?.sha256 == fingerprint.sha256 }
    }

    func filesForRefresh() async throws -> MusicFolderScan {
        let directory = root
        return try await Task.detached(priority: .userInitiated) { try MusicFolderScan.scan(directory) }.value
    }

    func unindexedFiles(_ files: [URL]) -> [URL] {
        let indexed = Set(index.tracks(inFolder: nil).map(\.filename))
        return files.filter { url in
            MusicFolderScan.relativePath(of: url, in: root).map { !indexed.contains($0) } ?? false
        }
    }

    /// Drops songs whose files were deleted from Harmony's folder (for example in the Files app).
    func removeMissingFiles() throws -> [LocalTrack] {
        // Never treat an unreadable folder as an empty one.
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        // Linked folders are checked by their own scans.
        let missing = index.tracks(inFolder: nil).filter {
            !FileManager.default.fileExists(atPath: root.appendingPathComponent($0.filename).path)
        }
        guard !missing.isEmpty else { return [] }
        var updated = index
        for track in missing { updated.remove(track.id) }
        try save(updated)
        deleteArtwork(of: missing)
        return missing
    }

    /// Updates legacy and changed files without loading their contents into memory.
    func refreshFingerprints(progress: ((Int, Int) -> Void)? = nil) async throws -> [String] {
        var updated = index
        var failures: [String] = []
        var changed = false
        let tracks = index.tracks
        progress?(0, tracks.count)
        for (position, track) in tracks.enumerated() {
            defer { progress?(position + 1, tracks.count) }
            // Unreachable or since-removed linked files are left to the folder's next scan.
            guard let url = url(for: track),
                track.folderID == nil || FileManager.default.fileExists(atPath: url.path)
            else { continue }
            do {
                let fingerprint = try await Self.fingerprint(url, cached: track.fingerprint)
                if fingerprint != track.fingerprint {
                    updated.setFingerprint(fingerprint, for: track.id)
                    changed = true
                }
            } catch {
                updated.setFingerprint(nil, for: track.id)
                if track.fingerprint != nil { changed = true }
                failures.append("\(track.originalFilename ?? track.filename): \(error.localizedDescription)")
            }
        }
        if changed { try save(updated) }
        return failures
    }

    private nonisolated static func fingerprint(_ url: URL, cached: FileFingerprint? = nil) async throws
        -> FileFingerprint
    {
        try await Task.detached(priority: .userInitiated) {
            var coordinationError: NSError?
            var result: Result<FileFingerprint, Error>?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinated in
                result = Result { try FileFingerprint.read(coordinated, cached: cached) }
            }
            if let coordinationError { throw coordinationError }
            guard let result else { throw CocoaError(.fileReadUnknown) }
            return try result.get()
        }.value
    }

    /// Files the system hands Harmony as private copies: the picker's and "Open in" inboxes.
    private nonisolated static func isAppOwnedTemporary(_ url: URL) -> Bool {
        var roots = [FileManager.default.temporaryDirectory]
        if let documents = try? FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        {
            roots.append(documents.appendingPathComponent("Inbox", isDirectory: true))
        }
        return roots.contains { MusicFolderScan.relativePath(of: url, in: $0) != nil }
    }

    private nonisolated static func seconds(_ duration: Double?) -> Int? {
        duration.flatMap { $0.isFinite ? Int(max(0, $0)) : nil }
    }

    private nonisolated static func title(fromFilename name: String) -> String {
        URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
    }

    private func embeddedArtwork(in url: URL) async -> Data? {
        if url.pathExtension.lowercased() == "flac",
            let data = try? await Task.detached(priority: .utility, operation: { try FLACArtwork.image(in: url) })
                .value,
            UIImage(data: data) != nil
        {
            return data
        }
        let asset = AVURLAsset(url: url)
        var metadata = (try? await asset.load(.commonMetadata)) ?? []
        metadata += (try? await asset.load(.metadata)) ?? []
        for format in (try? await asset.load(.availableMetadataFormats)) ?? [] {
            metadata += (try? await asset.loadMetadata(for: format)) ?? []
        }
        for item in metadata {
            guard
                item.commonKey == .commonKeyArtwork || item.identifier == .commonIdentifierArtwork
                    || item.identifier == .iTunesMetadataCoverArt || item.identifier == .id3MetadataAttachedPicture
            else { continue }
            if let data = try? await item.load(.dataValue), UIImage(data: data) != nil { return data }
        }
        return nil
    }

    /// Re-reads tags when forced or when the reader version changes, and restores artwork whose saved
    /// copy has gone missing. Other files are not reopened, so launch-time checks stay cheap.
    /// One unreadable file is reported and skipped; the index is written once at the end.
    func refreshImportedMetadata(force: Bool = false) async throws -> MetadataRefreshResult {
        var result = MetadataRefreshResult()
        var updated = index
        for track in index.tracks {
            guard let url = url(for: track), FileManager.default.fileExists(atPath: url.path) else { continue }
            let needsMetadata = force || track.metadataVersion != LocalMetadataReader.version
            let artworkMissing =
                track.artworkFilename.map {
                    !FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path)
                } ?? false
            guard needsMetadata || artworkMissing else { continue }
            do {
                // Missing artwork that can't be recovered is cleared so it isn't retried on every launch.
                var artworkFilename = artworkMissing ? nil : track.artworkFilename
                if let data = await embeddedArtwork(in: url) {
                    let filename = track.id + ".artwork"
                    try data.write(to: root.appendingPathComponent(filename), options: .atomic)
                    artworkFilename = filename
                }
                let song = track.song
                let refreshed: LocalTrack
                if needsMetadata {
                    // Tags read from the file are authoritative, so removed tags are cleared too.
                    let metadata = try await LocalMetadataReader.read(url)
                    let fallbackTitle = track.originalFilename.map(Self.title(fromFilename:)) ?? song.title
                    refreshed = LocalTrack(
                        id: track.id, filename: track.filename, title: metadata.title ?? fallbackTitle,
                        artist: metadata.artist, album: metadata.album, albumArtist: metadata.albumArtist,
                        duration: Self.seconds(metadata.duration) ?? song.duration,
                        track: metadata.track, disc: metadata.disc, artworkFilename: artworkFilename,
                        lyrics: metadata.lyrics, added: track.added, metadata: metadata,
                        originalFilename: track.originalFilename, metadataVersion: LocalMetadataReader.version,
                        fingerprint: track.fingerprint, edits: track.edits, folderID: track.folderID)
                } else {
                    refreshed = LocalTrack(
                        id: track.id, filename: track.filename, title: song.title, artist: song.artist,
                        album: song.album, albumArtist: song.albumArtist, duration: song.duration,
                        track: song.track, disc: song.discNumber, artworkFilename: artworkFilename,
                        lyrics: track.lyrics, added: track.added, metadata: track.metadata,
                        originalFilename: track.originalFilename, metadataVersion: track.metadataVersion,
                        fingerprint: track.fingerprint, edits: track.edits, folderID: track.folderID)
                }
                updated.replace(refreshed)
                result.changed = true
            } catch {
                result.failures.append("\(track.originalFilename ?? track.filename): \(error.localizedDescription)")
            }
        }
        if result.changed {
            artworkKeys = [:]
            try save(updated)
        }
        return result
    }

    /// Saves edited tag values in the index; the audio file isn't changed.
    func edit(_ id: String, fields: TrackFields) throws {
        guard let track = index.tracks.first(where: { $0.id == id }) else { throw LocalLibraryError.missing }
        var updated = index
        updated.replace(track.editing(fields))
        try save(updated)
    }

    /// Deletes an imported copy. A linked song is only hidden: its file stays in the folder.
    func remove(_ id: String) throws {
        guard let track = index.tracks.first(where: { $0.id == id }) else { return }
        if track.folderID != nil {
            var updated = index
            updated.hide(id)
            try save(updated)
            deleteArtwork(of: [track])
            return
        }
        let previous = index
        var updated = index
        updated.remove(id)
        try save(updated)
        let file = root.appendingPathComponent(track.filename)
        do {
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        } catch {
            try save(previous)
            throw error
        }
        if let art = track.artworkFilename { try? FileManager.default.removeItem(at: root.appendingPathComponent(art)) }
    }
    func fileURL(_ id: String) throws -> URL {
        guard let track = index.tracks.first(where: { $0.id == id }) else { throw LocalLibraryError.missing }
        guard let url = url(for: track) else {
            throw LocalLibraryError.folderUnavailable(track.folderID.flatMap(index.folder)?.name ?? "Linked folder")
        }
        if track.folderID != nil {
            // Ask iCloud for songs that aren't on the device. Current files are left alone, and
            // reading a dataless file downloads it on demand.
            let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                .ubiquitousItemDownloadingStatus
            if let status, status != .current { try? FileManager.default.startDownloadingUbiquitousItem(at: url) }
            if !FileManager.default.fileExists(atPath: url.path) {
                let placeholder = url.deletingLastPathComponent().appendingPathComponent(
                    ".\(url.lastPathComponent).icloud")
                if FileManager.default.fileExists(atPath: placeholder.path) {
                    throw LocalLibraryError.downloading(track.song.title)
                }
                throw LocalLibraryError.missingFromFolder(index.folder(track.folderID ?? "")?.name ?? "its folder")
            }
        }
        guard FileManager.default.fileExists(atPath: url.path) else { throw LocalLibraryError.missing }
        return url
    }
    func artwork(_ id: String) async throws -> Data {
        guard let filename = index.tracks.first(where: { $0.id == id })?.artworkFilename else {
            throw LocalLibraryError.missing
        }
        let url = root.appendingPathComponent(filename)
        // Keep file reads off the main actor while artwork scrolls into view.
        return try await Task.detached(priority: .userInitiated) { try Data(contentsOf: url) }.value
    }
    /// Identifies a song's cover by its image data. Songs from one album each save their own copy
    /// of the cover, so their IDs differ while the picture is the same.
    func cachedArtworkKey(_ id: String) -> String? { artworkKeys[id] }
    /// Hashes the cover off the main thread; nil when the song has no cover.
    func loadArtworkKey(_ id: String) async -> String? {
        if let key = artworkKeys[id] { return key }
        guard let filename = index.tracks.first(where: { $0.id == id })?.artworkFilename else { return nil }
        let url = root.appendingPathComponent(filename)
        let key = await Task.detached(priority: .utility) {
            (try? Data(contentsOf: url)).map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() }
        }.value
        if let key { artworkKeys[id] = key }
        return key
    }
    func album(_ id: String) async throws -> Album {
        guard let album = albums.first(where: { $0.id == id }) else { throw LocalLibraryError.missing }
        return album
    }
    func lyrics(for song: Song) async throws -> [StructuredLyrics] {
        guard let track = index.tracks.first(where: { $0.id == song.id }) else { return [] }
        var texts: [String] = []
        for key in ["SYNCEDLYRICS", "LYRICS", "UNSYNCEDLYRICS", "UNSYNCHRONIZEDLYRICS"] {
            for text in track.metadata?.values(key) ?? [] where !texts.contains(text) { texts.append(text) }
        }
        if texts.isEmpty, let text = track.lyrics, !text.isEmpty { texts = [text] }
        return texts.map { EmbeddedLyrics.parse($0, artist: song.artistName, title: song.title) }.filter(\.hasContent)
    }

}

enum LocalLibraryError: LocalizedError {
    case missing, unsupported(String), folderUnavailable(String), downloading(String), ownFolder
    case missingFromFolder(String)
    var errorDescription: String? {
        switch self {
        case .missing: "This file is no longer in Harmony. Import it again from Files."
        case .unsupported(let name): "\(name) could not be imported. Choose an audio file supported by your device."
        case .folderUnavailable(let name):
            "Harmony can’t open “\(name)”. Reconnect it in Settings → Music Folders."
        case .downloading(let title): "“\(title)” is downloading from iCloud. Try again in a moment."
        case .missingFromFolder(let name):
            "This song is no longer in “\(name)”. It was moved or deleted in Files; rescan the folder in Settings → Music Folders."
        case .ownFolder: "That’s Harmony’s own music folder. Choose a folder elsewhere, such as in iCloud Drive."
        }
    }
}
