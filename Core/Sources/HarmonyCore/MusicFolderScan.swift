import Foundation

public struct MusicFolderScan: Sendable {
    public let files: [URL]
    public let warnings: [String]

    /// Discovery only. The importer checks actual playability before adding a file.
    public static func scan(_ directory: URL) throws -> MusicFolderScan {
        let rootValues = try directory.resourceValues(forKeys: [.isDirectoryKey])
        guard rootValues.isDirectory == true else {
            throw NSError(
                domain: NSCocoaErrorDomain, code: CocoaError.fileReadUnknown.rawValue,
                userInfo: [NSLocalizedDescriptionKey: "Choose a folder containing music."])
        }
        let extensions: Set<String> = [
            "mp3", "m4a", "m4b", "m4p", "aac", "alac", "flac", "wav", "wave",
            "aif", "aiff", "aifc", "caf", "mp2", "ogg", "oga", "opus", "wma", "ape", "wv", "dsf", "dff",
        ]
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
        var warnings: [String] = []
        guard
            let enumerator = FileManager.default.enumerator(
                at: directory, includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { url, error in
                    warnings.append("\(url.lastPathComponent): \(error.localizedDescription)")
                    return true
                })
        else {
            throw NSError(
                domain: NSCocoaErrorDomain, code: CocoaError.fileReadUnknown.rawValue,
                userInfo: [NSLocalizedDescriptionKey: "This folder couldn’t be read. Choose it again in Files."])
        }
        var files: [URL] = []
        for case let url as URL in enumerator {
            do {
                let values = try url.resourceValues(forKeys: keys)
                if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                guard values.isRegularFile == true, extensions.contains(url.pathExtension.lowercased()) else {
                    continue
                }
                files.append(url)
            } catch { warnings.append("\(url.lastPathComponent): \(error.localizedDescription)") }
        }
        return MusicFolderScan(
            files: files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }, warnings: warnings)
    }
}
