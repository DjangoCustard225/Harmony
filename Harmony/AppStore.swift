import SwiftUI
import Observation
import HarmonyCore

@MainActor
@Observable
final class AppStore {
    private(set) var library: LocalMusicLibrary?
    private(set) var sessionID = UUID()
    private(set) var albums: [Album] = []
    private(set) var artists: [Artist] = []
    private(set) var songs: [Song] = []
    var albumOrder =
        AlbumOrder(rawValue: UserDefaults.standard.string(forKey: "albumOrder") ?? "") ?? .alphabeticalByName
    {
        didSet {
            UserDefaults.standard.set(albumOrder.rawValue, forKey: "albumOrder")
            refreshLibrary()
        }
    }
    var songOrder = SongSortOrder(rawValue: UserDefaults.standard.string(forKey: "songSortOrder") ?? "") ?? .title {
        didSet {
            UserDefaults.standard.set(songOrder.rawValue, forKey: "songSortOrder")
            refreshSongOrder()
        }
    }
    var songSortReversed = UserDefaults.standard.bool(forKey: "songSortReversed") {
        didSet {
            UserDefaults.standard.set(songSortReversed, forKey: "songSortReversed")
            refreshSongOrder()
        }
    }
    var notice: String?
    var importMode: MusicImportMode?
    private(set) var importing = false
    private(set) var refreshingMetadata = false
    private(set) var refreshingLibrary = false
    private(set) var reviewingDuplicates = false
    private(set) var duplicateGroups: [[LocalTrack]] = []
    private(set) var duplicateWarnings: [String] = []
    private(set) var duplicateProgress = ""
    private(set) var duplicateResult: String?
    private(set) var duplicateScanFailed = false
    private(set) var removingDuplicates = false
    var libraryBusy: Bool { importing || refreshingMetadata || refreshingLibrary || reviewingDuplicates }
    private(set) var importProgress = ""
    private struct ImportSummary {
        var added = 0
        var duplicates = 0
        /// Identical copies deleted from Harmony's own folder during a refresh.
        var removedCopies = 0
        var missing = 0
        var failures: [String] = []
        mutating func merge(_ other: ImportSummary) {
            added += other.added
            duplicates += other.duplicates
            removedCopies += other.removedCopies
            missing += other.missing
            failures += other.failures
        }
    }
    private enum ImportSelection {
        case files([URL])
        case folder(URL)
    }
    private var pendingImports: [ImportSelection] = []
    let player: PlayerStore
    let artwork: ArtworkCache
    let appearance = ArtworkAppearance()
    let artistProfiles = ArtistProfileStore()

    init() {
        let artwork = ArtworkCache()
        self.artwork = artwork
        self.player = PlayerStore(artwork: artwork)
        do {
            let library = try LocalMusicLibrary()
            self.library = library
            player.configure(library: library)
            refreshLibrary()
        } catch { notice = "Your library couldn't be opened: \(error.localizedDescription)" }
    }
    func refreshImportedMetadata(force: Bool = false) async {
        guard !libraryBusy else { return }
        refreshingMetadata = true
        defer { refreshingMetadata = false; Task { await processImports() } }
        do {
            guard let result = try await library?.refreshImportedMetadata(force: force) else { return }
            if result.changed { libraryDidChange(refreshPlayerMetadata: true) }
            // The launch-time check stays silent; a requested refresh reports files it couldn't read.
            if force, !result.failures.isEmpty {
                notice =
                    "Couldn’t refresh \(result.failures.count) song\(result.failures.count == 1 ? "" : "s").\n\n"
                    + Self.list(result.failures)
            }
        } catch { notice = "Music metadata couldn't be refreshed: \(error.localizedDescription)" }
    }
    func refreshLibraryFromDisk() async {
        guard !libraryBusy, let library else { return }
        refreshingLibrary = true
        defer { refreshingLibrary = false; importProgress = ""; Task { await processImports() } }
        var missing: [LocalTrack] = []
        do {
            importProgress = "Finding music…"
            // Songs deleted from the folder in Files would otherwise only fail when played.
            missing = try library.removeMissingFiles()
            player.removeFromQueue(Set(missing.map(\.id)))
            let scan = try await library.filesForRefresh()
            var summary = await importBatch(library.unindexedFiles(scan.files), into: library, inPlace: true)
            summary.missing = missing.count
            summary.failures.insert(contentsOf: scan.warnings, at: 0)
            libraryDidChange()
            showImportSummary(summary, emptyMessage: "Harmony’s music folder is up to date.")
        } catch {
            if !missing.isEmpty { libraryDidChange() }
            notice = "Harmony’s music folder couldn’t be scanned: \(error.localizedDescription)"
        }
    }
    func refreshLibrary() {
        guard let library else { return }
        let index = library.index
        songs = index.songs(sortedBy: songOrder, reversed: songSortReversed)
        artists = index.artists
        let values = index.albums
        if albumOrder == .newest {
            let dates = Dictionary(grouping: index.tracks, by: { $0.song.albumId ?? "" })
                .mapValues { $0.map(\.added).max() ?? .distantPast }
            albums = values.sorted { (dates[$0.id] ?? .distantPast) > (dates[$1.id] ?? .distantPast) }
        } else {
            albums = values
        }
    }
    private func libraryDidChange(refreshPlayerMetadata: Bool = false) {
        artwork.clear()
        refreshLibrary()
        if refreshPlayerMetadata { player.refreshMetadata(songs) }
        sessionID = UUID()
    }
    private func refreshSongOrder() {
        guard let library else { return }
        songs = library.index.songs(sortedBy: songOrder, reversed: songSortReversed)
    }
    func playAlbum(_ album: Album, shuffle: Bool = false) async {
        guard let tracks = library?.index.albums.first(where: { $0.id == album.id })?.songs, !tracks.isEmpty else {
            return
        }
        player.play(tracks, at: shuffle ? Int.random(in: tracks.indices) : 0, shuffle: shuffle)
    }
    func importFiles(_ urls: [URL]) async {
        pendingImports.append(.files(urls))
        await processImports()
    }
    func importFolder(_ url: URL) async {
        pendingImports.append(.folder(url))
        await processImports()
    }
    private func processImports() async {
        guard !libraryBusy, !pendingImports.isEmpty, let library else { return }
        importing = true
        defer { importing = false; importProgress = "" }
        var summary = ImportSummary()
        while !pendingImports.isEmpty {
            switch pendingImports.removeFirst() {
            case .files(let urls): summary.merge(await importBatch(urls, into: library))
            case .folder(let url): summary.merge(await importDirectory(url, into: library))
            }
        }
        libraryDidChange()
        showImportSummary(summary, emptyMessage: "No songs were selected.")
    }
    private func showImportSummary(_ summary: ImportSummary, emptyMessage: String) {
        guard
            summary.added > 0 || summary.duplicates > 0 || summary.removedCopies > 0 || summary.missing > 0
                || !summary.failures.isEmpty
        else {
            notice = emptyMessage
            return
        }
        func count(_ value: Int, _ noun: String, _ plural: String? = nil) -> String {
            "\(value) \(value == 1 ? noun : plural ?? noun + "s")"
        }
        var parts = ["Added \(summary.added)."]
        if summary.duplicates > 0 { parts.append("Skipped \(count(summary.duplicates, "duplicate")).") }
        if summary.removedCopies > 0 {
            parts.append("Removed \(count(summary.removedCopies, "identical copy", "identical copies")).")
        }
        if summary.missing > 0 { parts.append("Removed \(count(summary.missing, "missing song")).") }
        var message = parts.joined(separator: " ")
        if !summary.failures.isEmpty {
            message += " Failed \(summary.failures.count).\n\n" + Self.list(summary.failures)
        }
        notice = message
    }
    private static func list(_ failures: [String]) -> String {
        var text = failures.prefix(5).joined(separator: "\n\n")
        if failures.count > 5 { text += "\n\nAnd \(failures.count - 5) more items couldn’t be read." }
        return text
    }
    /// `inPlace` indexes files already in Harmony's folder instead of copying them in.
    private func importBatch(_ urls: [URL], into library: LocalMusicLibrary, inPlace: Bool = false) async
        -> ImportSummary
    {
        var summary = ImportSummary()
        importProgress = "Checking existing songs…"
        do { summary.failures += try await library.refreshFingerprints() } catch {
            summary.failures.append("Couldn’t check existing songs: \(error.localizedDescription)")
            return summary
        }
        for (index, url) in urls.enumerated() {
            importProgress = "Importing \(index + 1) of \(urls.count)…"
            do {
                switch try await inPlace ? library.addExistingFile(url) : library.importFile(url) {
                case .added: summary.added += 1
                case .duplicate where inPlace: summary.removedCopies += 1
                case .duplicate: summary.duplicates += 1
                }
            } catch {
                summary.failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return summary
    }
    private func importDirectory(_ directory: URL, into library: LocalMusicLibrary) async -> ImportSummary {
        // The folder picker delivers an app-owned temporary copy in folder mode.
        defer { try? FileManager.default.removeItem(at: directory) }
        let access = directory.startAccessingSecurityScopedResource()
        // Keep the parent grant active until every discovered child has been copied.
        defer { if access { directory.stopAccessingSecurityScopedResource() } }
        importProgress = "Finding music in \(directory.lastPathComponent)…"
        do {
            let scan = try await Task.detached(priority: .userInitiated) {
                var coordinationError: NSError?
                var scanResult: Result<MusicFolderScan, Error>?
                NSFileCoordinator().coordinate(readingItemAt: directory, options: [], error: &coordinationError) {
                    url in
                    scanResult = Result { try MusicFolderScan.scan(url) }
                }
                if let error = coordinationError { throw error }
                guard let scanResult else { throw CocoaError(.fileReadUnknown) }
                return try scanResult.get()
            }.value
            guard !scan.files.isEmpty else {
                var result = ImportSummary()
                result.failures =
                    scan.warnings.isEmpty
                    ? ["No audio files were found in this folder or its subfolders."] : scan.warnings
                return result
            }
            var result = await importBatch(scan.files, into: library)
            result.failures.insert(contentsOf: scan.warnings, at: 0)
            return result
        } catch {
            var result = ImportSummary()
            result.failures = ["\(directory.lastPathComponent): \(error.localizedDescription)"]
            return result
        }
    }
    func scanDuplicates() async {
        guard !libraryBusy, let library else { return }
        reviewingDuplicates = true
        duplicateResult = nil
        duplicateScanFailed = false
        duplicateWarnings = []
        defer { reviewingDuplicates = false; Task { await processImports() } }
        do {
            duplicateWarnings = try await library.refreshFingerprints { checked, total in
                self.duplicateProgress = "Checked \(checked) of \(total) songs"
            }
            duplicateGroups = library.index.duplicateGroups
        } catch { duplicateWarnings = [error.localizedDescription]; duplicateScanFailed = true }
    }
    /// A nil selection removes every duplicate after a fresh scan, keeping the oldest copy.
    func removeDuplicates(_ ids: Set<String>? = nil) async {
        guard !libraryBusy, let library, ids?.isEmpty != true else { return }
        reviewingDuplicates = true
        removingDuplicates = true
        duplicateResult = nil
        duplicateScanFailed = false
        defer { reviewingDuplicates = false; removingDuplicates = false; Task { await processImports() } }
        do {
            duplicateWarnings = try await library.refreshFingerprints { checked, total in
                self.duplicateProgress = "Rechecking \(checked) of \(total) songs"
            }
            let currentGroups = library.index.duplicateGroups
            var removed = 0
            var removedBytes: Int64 = 0
            for group in currentGroups {
                let chosen =
                    ids.map { selection in group.filter { selection.contains($0.id) } }
                    ?? Array(group.dropFirst())
                guard !chosen.isEmpty, chosen.count < group.count else { continue }
                let chosenIDs = Set(chosen.map(\.id))
                // The group always keeps at least one copy; queued copies switch to it seamlessly.
                guard let kept = group.first(where: { !chosenIDs.contains($0.id) }) else { continue }
                for track in chosen {
                    do {
                        try library.remove(track.id)
                        player.removeFromQueue([], replacements: [track.id: kept.song])
                        removed += 1
                        removedBytes += track.fingerprint?.size ?? 0
                    } catch { duplicateWarnings.append("\(track.song.title): \(error.localizedDescription)") }
                    duplicateProgress = "Removed \(removed) copies"
                    await Task.yield()
                }
            }
            duplicateGroups = library.index.duplicateGroups
            if removed > 0 { libraryDidChange() }
            duplicateResult =
                removed == 0
                ? "No copies removed. The library may have changed."
                : "Removed \(removed) duplicate\(removed == 1 ? "" : "s") · \(ByteCountFormatter.string(fromByteCount: removedBytes, countStyle: .file)) freed"
        } catch { duplicateWarnings = [error.localizedDescription]; duplicateScanFailed = true }
    }
    func removeSong(_ song: Song) {
        guard !libraryBusy else { notice = "Wait for the library operation to finish."; return }
        do {
            try library?.remove(song.id)
            player.removeFromQueue([song.id])
            libraryDidChange()
        } catch { notice = error.localizedDescription }
    }
}
