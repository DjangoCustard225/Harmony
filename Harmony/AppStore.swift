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
        var moved = 0
        var downloading = 0
        var failures: [String] = []
        var changedLibrary: Bool { added > 0 || removedCopies > 0 || missing > 0 || moved > 0 }
        mutating func merge(_ other: ImportSummary) {
            added += other.added
            duplicates += other.duplicates
            removedCopies += other.removedCopies
            missing += other.missing
            moved += other.moved
            downloading += other.downloading
            failures += other.failures
        }
    }
    private enum ImportSelection {
        case files([URL])
        case folder(URL)
        /// Links a folder, or reconnects the linked folder with the given ID.
        case link(URL, replacing: String?)
        /// Rescans a linked folder. Quiet rescans (at launch) only report through the library.
        case sync(String, quiet: Bool)
    }
    /// Set before showing the folder picker to reconnect a linked folder instead of adding one.
    var reconnectingFolderID: String?
    private var pendingImports: [ImportSelection] = []
    private let playlistLibrary: PlaylistLibrary?
    private(set) var playlists: [Playlist] = []
    /// Songs waiting for a name from the "New Playlist" prompt; an empty list makes an empty playlist.
    var newPlaylistRequest: [Song]?
    /// Bumped whenever `refreshLibrary` reads the index, for views that read it directly.
    private(set) var libraryRevision = 0
    /// Library songs by ID, for resolving playlists without rebuilding a lookup each time.
    private var songsByID: [String: Song] = [:]
    let player: PlayerStore
    let artwork: ArtworkCache
    let appearance = ArtworkAppearance()
    let artistProfiles = ArtistProfileStore()

    init() {
        let artwork = ArtworkCache()
        self.artwork = artwork
        self.player = PlayerStore(artwork: artwork)
        let playlistLibrary = try? PlaylistLibrary()
        self.playlistLibrary = playlistLibrary
        playlists = playlistLibrary?.collection.playlists ?? []
        if let error = playlistLibrary?.loadError {
            notice = "Your playlists couldn't be read: \(error.localizedDescription)"
        }
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
            syncPlaylists { $0.removeSongs(Set(missing.map(\.id))) }
            let scan = try await library.filesForRefresh()
            var summary = await importBatch(library.unindexedFiles(scan.files), into: library, inPlace: true)
            summary.missing += missing.count
            summary.failures.insert(contentsOf: scan.warnings, at: 0)
            for folder in library.index.folders {
                summary.merge(await syncFolder(folder.id, in: library))
            }
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
        libraryRevision += 1
        songs = index.songs(sortedBy: songOrder, reversed: songSortReversed)
        songsByID = Dictionary(index.tracks.map { ($0.id, $0.song) }, uniquingKeysWith: { first, _ in first })
        let values = library.albums
        artists = LocalLibraryIndex.artists(from: values)
        if albumOrder == .newest {
            let dates = Dictionary(grouping: index.tracks, by: { $0.song.albumId ?? "" })
                .mapValues { $0.map(\.added).max() ?? .distantPast }
            albums = values.sorted { (dates[$0.id] ?? .distantPast) > (dates[$1.id] ?? .distantPast) }
        } else {
            albums = values
        }
    }
    /// `refreshPlayerMetadata` is for tag rereads, which can also replace artwork; imports and
    /// removals only add or drop IDs, so cached artwork stays valid.
    private func libraryDidChange(refreshPlayerMetadata: Bool = false) {
        if refreshPlayerMetadata { artwork.clear() }
        refreshLibrary()
        if refreshPlayerMetadata { player.refreshMetadata(songs) }
        sessionID = UUID()
    }
    private func refreshSongOrder() {
        guard let library else { return }
        songs = library.index.songs(sortedBy: songOrder, reversed: songSortReversed)
    }
    func playAlbum(_ album: Album, shuffle: Bool = false) async {
        guard let tracks = albums.first(where: { $0.id == album.id })?.songs, !tracks.isEmpty else {
            return
        }
        player.play(tracks, at: shuffle ? Int.random(in: tracks.indices) : 0, shuffle: shuffle)
    }

    // MARK: Playlists

    func playlist(_ id: String) -> Playlist? { playlists.first { $0.id == id } }
    /// Entries whose songs are still in the library; songs removed elsewhere are hidden.
    func entries(in playlist: Playlist) -> [PlaylistEntry] {
        PlaylistCollection.entries(in: playlist, songs: songsByID)
    }
    func songs(in playlist: Playlist) -> [Song] { entries(in: playlist).map(\.song) }
    /// Up to four different covers from the most recently added songs, newest first, for a
    /// split cover. Songs sharing an album, or an identical picture, count as one cover.
    func playlistCovers(_ songs: [Song]) -> [String] {
        _ = artworkKeysRevision
        var albums = Set<String>()
        var pictures = Set<String>()
        var covers: [String] = []
        for song in songs.reversed() {
            guard covers.count < 4 else { break }
            guard let cover = song.coverArt else { continue }
            if let album = song.albumId, !albums.insert(album).inserted { continue }
            let key = library?.cachedArtworkKey(cover)
            if key == nil { requestArtworkKey(cover) }
            guard pictures.insert(key ?? cover).inserted else { continue }
            covers.append(cover)
        }
        return covers
    }
    /// Bumped once a batch of cover hashes finishes, so split covers redraw a single time.
    private(set) var artworkKeysRevision = 0
    @ObservationIgnored private var pendingArtworkKeys: Set<String> = []
    private func requestArtworkKey(_ id: String) {
        guard let library, pendingArtworkKeys.insert(id).inserted else { return }
        Task {
            _ = await library.loadArtworkKey(id)
            pendingArtworkKeys.remove(id)
            if pendingArtworkKeys.isEmpty { artworkKeysRevision += 1 }
        }
    }
    @discardableResult
    func createPlaylist(name: String, songs: [Song] = []) -> Playlist? {
        changePlaylists { $0.create(name: name, songIDs: songs.map(\.id)) }
    }
    func renamePlaylist(_ playlist: Playlist, to name: String) {
        changePlaylists { $0.rename(playlist.id, to: name) }
    }
    func deletePlaylist(_ playlist: Playlist) {
        changePlaylists { $0.delete(playlist.id) }
    }
    func addToPlaylist(_ songs: [Song], _ playlist: Playlist) {
        changePlaylists { $0.add(songs.map(\.id), to: playlist.id) }
    }
    /// `offsets` index the visible entries shown for the playlist.
    func removeFromPlaylist(_ playlist: Playlist, at offsets: IndexSet, entries: [PlaylistEntry]) {
        let stored = IndexSet(offsets.compactMap { entries.indices.contains($0) ? entries[$0].position : nil })
        changePlaylists { $0.remove(at: stored, from: playlist.id) }
    }
    func movePlaylistSongs(
        _ playlist: Playlist, from offsets: IndexSet, to destination: Int, entries: [PlaylistEntry]
    ) {
        let move = PlaylistCollection.storedMove(
            from: offsets, to: destination, entries: entries, storedCount: playlist.songIDs.count)
        changePlaylists { $0.move(from: move.offsets, to: move.destination, in: playlist.id) }
    }
    func playPlaylist(_ playlist: Playlist, shuffle: Bool = false) {
        let tracks = songs(in: playlist)
        guard !tracks.isEmpty else { return }
        player.play(tracks, at: shuffle ? Int.random(in: tracks.indices) : 0, shuffle: shuffle)
    }
    @discardableResult
    private func changePlaylists<Result>(_ change: (inout PlaylistCollection) -> Result) -> Result? {
        guard let playlistLibrary else {
            notice = "Playlists are unavailable. Restart Harmony to try again."
            return nil
        }
        do {
            let result = try playlistLibrary.update(change)
            playlists = playlistLibrary.collection.playlists
            return result
        } catch {
            notice = "Your playlists couldn't be saved: \(error.localizedDescription)"
            return nil
        }
    }
    /// Keeps playlists in step with library removals. Saves only when something changed, and never
    /// overwrites a playlist file that couldn't be read.
    private func syncPlaylists(_ change: (inout PlaylistCollection) -> Bool) {
        guard let playlistLibrary, playlistLibrary.loadError == nil else { return }
        var probe = playlistLibrary.collection
        guard change(&probe) else { return }
        changePlaylists { _ = change(&$0) }
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
        var requested = false
        var emptyMessage = "No songs were selected."
        while !pendingImports.isEmpty {
            let selection = pendingImports.removeFirst()
            if case .sync(_, quiet: true) = selection {} else { requested = true }
            switch selection {
            case .files(let urls): summary.merge(await importBatch(urls, into: library))
            case .folder(let url): summary.merge(await importDirectory(url, into: library))
            case .link(let url, let replacing):
                do {
                    let folder = try library.link(url, replacing: replacing)
                    emptyMessage = "“\(folder.name)” is linked and up to date."
                    summary.merge(await syncFolder(folder.id, in: library))
                } catch {
                    summary.failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            case .sync(let id, _): summary.merge(await syncFolder(id, in: library))
            }
        }
        // Launch-time rescans that found nothing stay out of the way.
        guard requested || summary.changedLibrary else { return }
        libraryDidChange()
        if requested { showImportSummary(summary, emptyMessage: emptyMessage) }
    }
    private func showImportSummary(_ summary: ImportSummary, emptyMessage: String) {
        guard
            summary.changedLibrary || summary.duplicates > 0 || summary.downloading > 0 || !summary.failures.isEmpty
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
        if summary.moved > 0 { parts.append("Updated \(count(summary.moved, "moved song")).") }
        if summary.missing > 0 { parts.append("Removed \(count(summary.missing, "missing song")).") }
        if summary.downloading > 0 {
            parts.append(
                "Downloading \(count(summary.downloading, "song")) from iCloud; they’ll be added on the next scan.")
        }
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
    // MARK: Linked folders

    /// Linked folders, refreshed with the library.
    var linkedFolders: [LinkedFolder] {
        _ = libraryRevision
        return library?.index.folders ?? []
    }
    func songCount(inFolder id: String) -> Int {
        _ = libraryRevision
        return library?.index.tracks(inFolder: id).count ?? 0
    }
    func isFolderAvailable(_ id: String) -> Bool {
        _ = libraryRevision
        return library?.isAvailable(id) ?? false
    }
    func linkFolder(_ url: URL) async {
        pendingImports.append(.link(url, replacing: reconnectingFolderID))
        reconnectingFolderID = nil
        await processImports()
    }
    func rescanFolder(_ id: String) async {
        pendingImports.append(.sync(id, quiet: false))
        await processImports()
    }
    /// Picks up changes made in Files while Harmony was away. Folders scanned within the last
    /// `minimumInterval` are skipped, so returning to the app often stays cheap.
    func rescanLinkedFolders(minimumInterval: TimeInterval = 120) async {
        guard let library else { return }
        let queued = pendingImports.contains {
            if case .sync = $0 { return true }
            return false
        }
        guard !queued else { return }
        let due = library.index.folders.filter {
            library.isAvailable($0.id) && Date().timeIntervalSince($0.lastScan ?? .distantPast) > minimumInterval
        }
        guard !due.isEmpty else { return }
        pendingImports += due.map { .sync($0.id, quiet: true) }
        await processImports()
    }
    func unlinkFolder(_ id: String) {
        guard !libraryBusy else { notice = "Wait for the library operation to finish."; return }
        guard let library else { return }
        do {
            let removed = Set(try library.unlink(id).map(\.id))
            player.removeFromQueue(removed)
            syncPlaylists { $0.removeSongs(removed) }
            libraryDidChange()
        } catch { notice = "The folder couldn’t be unlinked: \(error.localizedDescription)" }
    }
    func showHiddenSongs(inFolder id: String) async {
        guard !libraryBusy else { notice = "Wait for the library operation to finish."; return }
        do { try library?.showHidden(in: id) } catch { notice = error.localizedDescription; return }
        await rescanFolder(id)
    }
    private func syncFolder(_ id: String, in library: LocalMusicLibrary) async -> ImportSummary {
        var summary = ImportSummary()
        do {
            let result = try await library.syncFolder(id) { self.importProgress = $0 }
            let removed = Set(result.removed.map(\.id))
            player.removeFromQueue(removed)
            syncPlaylists { $0.removeSongs(removed) }
            summary.added = result.added
            summary.duplicates = result.duplicates
            summary.moved = result.moved
            summary.missing = result.removed.count
            summary.downloading = result.downloading
            summary.failures = result.failures
        } catch {
            summary.failures = [error.localizedDescription]
        }
        return summary
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
                        syncPlaylists { $0.replaceSong(track.id, with: kept.id) }
                        removed += 1
                        // Linked songs are only hidden, so they free no space.
                        if track.folderID == nil { removedBytes += track.fingerprint?.size ?? 0 }
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
    /// The indexed track for `id`. Reading it updates views when the library changes.
    func track(_ id: String) -> LocalTrack? {
        _ = libraryRevision
        return library?.index.tracks.first { $0.id == id }
    }
    /// Saves edited tags. Open pages stay put, so the session (and navigation) isn't reset.
    func editTrack(_ id: String, fields: TrackFields) -> Bool {
        guard !libraryBusy else { notice = "Wait for the library operation to finish."; return false }
        do {
            try library?.edit(id, fields: fields)
            refreshLibrary()
            player.refreshMetadata(songs)
            return true
        } catch {
            notice = "The song couldn’t be updated: \(error.localizedDescription)"
            return false
        }
    }
    func removeSong(_ song: Song) {
        guard !libraryBusy else { notice = "Wait for the library operation to finish."; return }
        do {
            try library?.remove(song.id)
            player.removeFromQueue([song.id])
            syncPlaylists { $0.removeSongs([song.id]) }
            libraryDidChange()
        } catch { notice = error.localizedDescription }
    }
}
