import Foundation

/// Shared bounded reader for native FLAC metadata. Returning false from visit stops the scan.
enum FLACMetadataBlocks {
    @discardableResult
    static func read(in url: URL, including types: Set<UInt8>, visit: (UInt8, Data) -> Bool) throws -> Bool {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        guard try file.read(upToCount: 4) == Data("fLaC".utf8) else { return false }
        var totalBytes = 0
        while let header = try file.read(upToCount: 4), header.count == 4 {
            let last = header[0] & 0x80 != 0
            let type = header[0] & 0x7f
            let size = Int(header[1]) << 16 | Int(header[2]) << 8 | Int(header[3])
            totalBytes += size
            guard totalBytes <= 64 * 1024 * 1024 else { break }
            if types.contains(type) {
                guard let block = try file.read(upToCount: size), block.count == size else { break }
                if !visit(type, block) { break }
            } else {
                try file.seek(toOffset: file.offset() + UInt64(size))
            }
            if last { break }
        }
        return true
    }
}
