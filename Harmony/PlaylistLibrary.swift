import Foundation
import HarmonyCore

/// Stores playlists in Playlists.json next to the music library's own index.
@MainActor
final class PlaylistLibrary {
    private let file: URL
    private(set) var collection = PlaylistCollection()
    /// Set when an existing file couldn't be read. It is left in place until the user changes a playlist.
    private(set) var loadError: Error?

    init() throws {
        let root = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        .appendingPathComponent("Music", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        file = root.appendingPathComponent("Playlists.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            collection = try JSONDecoder().decode(PlaylistCollection.self, from: Data(contentsOf: file))
        } catch {
            loadError = error
        }
    }

    /// Applies a change and saves it. Nothing changes in memory if the file can't be written.
    @discardableResult
    func update<Result>(_ change: (inout PlaylistCollection) -> Result) throws -> Result {
        var updated = collection
        let result = change(&updated)
        try JSONEncoder().encode(updated).write(to: file, options: .atomic)
        collection = updated
        loadError = nil
        return result
    }
}
