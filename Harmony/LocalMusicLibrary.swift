import AVFoundation
import UIKit
import HarmonyCore

enum MusicImportResult { case added, duplicate }

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
    func importFile(_ source: URL) async throws -> MusicImportResult {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let id = UUID().uuidString
        let filename = id + "." + source.pathExtension.lowercased()
        let destination = root.appendingPathComponent(filename)
        var committed = false
        let artworkName = id + ".artwork"
        defer {
            if !committed {
                try? FileManager.default.removeItem(at: destination)
                try? FileManager.default.removeItem(at: root.appendingPathComponent(artworkName))
            }
        }
        // File providers may need time to materialize cloud files; keep that work off the UI thread.
        try await Task.detached(priority: .userInitiated) {
            var coordinationError: NSError?
            var copyError: Error?
            NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { url in
                do { try FileManager.default.copyItem(at: url, to: destination) } catch { copyError = error }
            }
            if let error = coordinationError { throw error }
            if let error = copyError { throw error }
        }.value
        let fingerprint = try await Self.fingerprint(destination)
        if index.tracks.contains(where: {
            $0.fingerprint?.size == fingerprint.size && $0.fingerprint?.sha256 == fingerprint.sha256
        }) {
            return .duplicate
        }
        let asset = AVURLAsset(url: destination)
        guard try await asset.load(.isPlayable), !(try await asset.loadTracks(withMediaType: .audio)).isEmpty else {
            throw LocalLibraryError.unsupported(source.lastPathComponent)
        }
        let metadata = try await LocalMetadataReader.read(destination)
        var artworkFilename: String?
        if let data = await embeddedArtwork(in: destination) {
            try data.write(to: root.appendingPathComponent(artworkName), options: .atomic)
            artworkFilename = artworkName
        }
        let entry = LocalTrack(
            id: id, filename: filename, title: metadata.title ?? source.deletingPathExtension().lastPathComponent,
            artist: metadata.artist, album: metadata.album, albumArtist: metadata.albumArtist,
            duration: metadata.duration.flatMap { $0.isFinite ? Int(max(0, $0)) : nil },
            track: metadata.track, disc: metadata.disc, artworkFilename: artworkFilename, lyrics: metadata.lyrics,
            metadata: metadata, originalFilename: source.lastPathComponent,
            metadataVersion: LocalMetadataReader.version,
            fingerprint: fingerprint
        )
        var updated = index
        updated.append(entry)
        try save(updated)
        committed = true
        return .added
    }

    func filesForRefresh() async throws -> MusicFolderScan {
        let directory = root
        return try await Task.detached(priority: .userInitiated) { try MusicFolderScan.scan(directory) }.value
    }

    func isIndexedFile(_ url: URL) -> Bool {
        let path = url.standardizedFileURL
        return index.tracks.contains { root.appendingPathComponent($0.filename).standardizedFileURL == path }
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

    func refreshImportedMetadata(force: Bool = false) async throws -> Bool {
        var changed = false
        for track in index.tracks {
            let url = root.appendingPathComponent(track.filename)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let needsMetadata = force || track.metadataVersion != LocalMetadataReader.version
            var artworkFilename = track.artworkFilename
            var recoveredArtwork = false
            let artworkExists =
                artworkFilename.map {
                    FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path)
                } ?? false
            if !artworkExists, let data = await embeddedArtwork(in: url) {
                let filename = track.id + ".artwork"
                try data.write(to: root.appendingPathComponent(filename), options: .atomic)
                artworkFilename = filename
                recoveredArtwork = true
            }
            guard needsMetadata || recoveredArtwork else { continue }
            let metadata = needsMetadata ? try await LocalMetadataReader.read(url) : track.metadata
            guard index.tracks.contains(where: { $0.id == track.id }) else { continue }
            let song = track.song
            let updatedTrack = LocalTrack(
                id: track.id, filename: track.filename, title: metadata?.title ?? song.title,
                artist: metadata?.artist ?? song.artist, album: metadata?.album ?? song.album,
                albumArtist: metadata?.albumArtist ?? song.albumArtist,
                duration: metadata?.duration.flatMap { $0.isFinite ? Int(max(0, $0)) : nil } ?? song.duration,
                track: metadata?.track ?? song.track, disc: metadata?.disc ?? song.discNumber,
                artworkFilename: artworkFilename, lyrics: metadata?.lyrics ?? track.lyrics, added: track.added,
                metadata: metadata, originalFilename: track.originalFilename,
                metadataVersion: LocalMetadataReader.version, fingerprint: track.fingerprint)
            var updated = index
            updated.replace(updatedTrack)
            try save(updated)
            changed = true
        }
        return changed
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
