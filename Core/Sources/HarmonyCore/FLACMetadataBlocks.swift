import Foundation

/// Shared bounded reader for native FLAC metadata. Returning false from visit stops the scan.
enum FLACMetadataBlocks {
    @discardableResult
    static func read(in url: URL, including types: Set<UInt8>, visit: (UInt8, Data) -> Bool) throws -> Bool {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        // Some taggers prepend ID3v2 tags to FLAC; skip them to reach the native stream marker.
        var start: UInt64 = 0
        var prefix = try file.read(upToCount: 10) ?? Data()
        while prefix.count == 10, prefix.starts(with: Data("ID3".utf8)) {
            guard prefix[6..<10].allSatisfy({ $0 & 0x80 == 0 }) else { return false }
            let size = prefix[6..<10].reduce(UInt64(0)) { ($0 << 7) | UInt64($1) }
            start += 10 + size + (prefix[5] & 0x10 != 0 ? 10 : 0)
            try file.seek(toOffset: start)
            prefix = try file.read(upToCount: 10) ?? Data()
        }
        guard prefix.starts(with: Data("fLaC".utf8)) else { return false }
        try file.seek(toOffset: start + 4)
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
