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
    var albumOrder: AlbumOrder = .alphabeticalByName {
        didSet { refreshLibrary() }
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
    private(set) var importProgress = ""
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
        guard !refreshingMetadata else { return }
        refreshingMetadata = true
        defer { refreshingMetadata = false }
        do {
            if try await library?.refreshImportedMetadata(force: force) == true {
                libraryDidChange(refreshPlayerMetadata: true)
            }
        } catch { notice = "Music metadata couldn't be refreshed: \(error.localizedDescription)" }
    }
    func refreshLibraryFromDisk() async {
        guard !refreshingLibrary, !importing, let library else { return }
        refreshingLibrary = true
        defer { refreshingLibrary = false }
        do {
            let added = try await library.refreshLibrary()
            libraryDidChange()
            if added == 0 {
                notice = "Harmony’s music folder is up to date."
            } else {
                notice = "Added \(added) song\(added == 1 ? "" : "s") from Harmony’s music folder."
            }
        } catch { notice = "Harmony’s music folder couldn’t be scanned: \(error.localizedDescription)" }
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
        guard !importing, let library else { return }
        importing = true
        defer { importing = false; importProgress = "" }
        var failures: [String] = []
        while !pendingImports.isEmpty {
            switch pendingImports.removeFirst() {
            case .files(let urls): failures += await importBatch(urls, into: library)
            case .folder(let url): failures += await importDirectory(url, into: library)
            }
        }
        libraryDidChange()
        if !failures.isEmpty {
            var message = failures.prefix(5).joined(separator: "\n\n")
            if failures.count > 5 {
                message += "\n\nAnd \(failures.count - 5) more files or folders couldn’t be imported."
            }
            notice = message
        }
    }
    private func importBatch(_ urls: [URL], into library: LocalMusicLibrary) async -> [String] {
        var failures: [String] = []
        for (index, url) in urls.enumerated() {
            importProgress = "Importing \(index + 1) of \(urls.count)…"
            do { try await library.importFile(url) } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return failures
    }
    private func importDirectory(_ directory: URL, into library: LocalMusicLibrary) async -> [String] {
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
                return scan.warnings.isEmpty
                    ? ["No audio files were found in this folder or its subfolders."] : scan.warnings
            }
            return scan.warnings + (await importBatch(scan.files, into: library))
        } catch { return ["\(directory.lastPathComponent): \(error.localizedDescription)"] }
    }
    func removeSong(_ song: Song) {
        do {
            try library?.remove(song.id)
            // Stop queues that still reference the removed file.
            if player.queue.songs.contains(where: { $0.id == song.id }) { player.stop() }
            libraryDidChange()
        } catch { notice = error.localizedDescription }
    }
}
