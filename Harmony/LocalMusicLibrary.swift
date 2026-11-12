import AVFoundation
import UIKit
import HarmonyCore

enum MusicImportResult { case added, duplicate }

struct MetadataRefreshResult {
    var changed = false
    var failures: [String] = []
}

/// Owns imported copies: playback never depends on a provider URL or a network connection.
@MainActor
final class LocalMusicLibrary {
    private let root: URL
    private(set) var index = LocalLibraryIndex()
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
    }
    private func save(_ value: LocalLibraryIndex) throws {
        try JSONEncoder().encode(value).write(to: root.appendingPathComponent("Library.json"), options: .atomic)
        index = value
    }

    /// Copies a file into Harmony's folder. App-owned temporary copies (from the Files picker or
    /// another app's "Open in") are moved instead, and are never left behind.
    func importFile(_ source: URL) async throws -> MusicImportResult {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        // A file opened from Harmony's own folder in Files is already in place.
        if let filename = MusicFolderScan.relativePath(of: source, in: root) {
            if index.tracks.contains(where: { $0.filename == filename }) { return .duplicate }
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
            !index.tracks.contains(where: { $0.filename == filename })
        else { throw LocalLibraryError.unsupported(url.lastPathComponent) }
        let fingerprint = try await Self.fingerprint(url)
        if let original = track(matching: fingerprint) {
            // Only delete when the kept copy is still on disk.
            if FileManager.default.fileExists(atPath: root.appendingPathComponent(original.filename).path) {
                try FileManager.default.removeItem(at: url)
            }
            return .duplicate
        }
        return try await addTrack(
            id: UUID().uuidString, file: url, filename: filename, originalFilename: url.lastPathComponent,
            fingerprint: fingerprint)
    }

    private func addTrack(
        id: String, file: URL, filename: String, originalFilename: String, fingerprint known: FileFingerprint? = nil
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
            fingerprint: fingerprint
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
        let indexed = Set(index.tracks.map(\.filename))
        return files.filter { url in
            MusicFolderScan.relativePath(of: url, in: root).map { !indexed.contains($0) } ?? false
        }
    }

    /// Drops songs whose files were deleted from Harmony's folder (for example in the Files app).
    func removeMissingFiles() throws -> [LocalTrack] {
        // Never treat an unreadable folder as an empty one.
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let missing = index.tracks.filter {
            !FileManager.default.fileExists(atPath: root.appendingPathComponent($0.filename).path)
        }
        guard !missing.isEmpty else { return [] }
        var updated = index
        for track in missing { updated.remove(track.id) }
        try save(updated)
        for artwork in missing.compactMap(\.artworkFilename) {
            try? FileManager.default.removeItem(at: root.appendingPathComponent(artwork))
        }
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
            let url = root.appendingPathComponent(track.filename)
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
            progress?(position + 1, tracks.count)
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
            let url = root.appendingPathComponent(track.filename)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
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
                        fingerprint: track.fingerprint)
                } else {
                    refreshed = LocalTrack(
                        id: track.id, filename: track.filename, title: song.title, artist: song.artist,
                        album: song.album, albumArtist: song.albumArtist, duration: song.duration,
                        track: song.track, disc: song.discNumber, artworkFilename: artworkFilename,
                        lyrics: track.lyrics, added: track.added, metadata: track.metadata,
                        originalFilename: track.originalFilename, metadataVersion: track.metadataVersion,
                        fingerprint: track.fingerprint)
                }
                updated.replace(refreshed)
                result.changed = true
            } catch {
                result.failures.append("\(track.originalFilename ?? track.filename): \(error.localizedDescription)")
            }
        }
        if result.changed { try save(updated) }
        return result
    }

    func remove(_ id: String) throws {
        guard let track = index.tracks.first(where: { $0.id == id }) else { return }
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
        let url = root.appendingPathComponent(track.filename)
        guard FileManager.default.fileExists(atPath: url.path) else { throw LocalLibraryError.missing }
        return url
    }
    func artwork(_ id: String) async throws -> Data {
        guard let filename = index.tracks.first(where: { $0.id == id })?.artworkFilename else {
            throw LocalLibraryError.missing
        }
        return try Data(contentsOf: root.appendingPathComponent(filename))
    }
    func album(_ id: String) async throws -> Album {
        guard let album = index.albums.first(where: { $0.id == id }) else { throw LocalLibraryError.missing }
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
    case missing, unsupported(String)
    var errorDescription: String? {
        switch self {
        case .missing: "This file is no longer in Harmony. Import it again from Files."
        case .unsupported(let name): "\(name) could not be imported. Choose an audio file supported by your device."
        }
    }
}
