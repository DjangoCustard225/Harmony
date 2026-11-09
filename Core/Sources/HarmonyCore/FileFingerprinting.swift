#if canImport(CryptoKit)
    import CryptoKit
    import Foundation

    extension FileFingerprint {
        /// Reads a file incrementally and rejects files that change during hashing.
        public static func read(_ url: URL, cached: FileFingerprint? = nil) throws -> FileFingerprint {
            func stamp() throws -> (Int64, Date) {
                let values = try FileManager.default.attributesOfItem(atPath: url.path)
                guard let size = values[.size] as? NSNumber, let modified = values[.modificationDate] as? Date else {
                    throw CocoaError(.fileReadUnknown)
                }
                return (size.int64Value, modified)
            }
            let (size, modified) = try stamp()
            if let cached, cached.size == size, cached.modified == modified { return cached }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hash = SHA256()
            while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
                hash.update(data: chunk)
            }
            let (endSize, endModified) = try stamp()
            guard size == endSize, modified == endModified else { throw CocoaError(.fileReadUnknown) }
            let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
            return FileFingerprint(sha256: digest, size: size, modified: modified)
        }
    }
#endif
