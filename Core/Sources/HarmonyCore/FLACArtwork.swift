import Foundation

/// Reads FLAC PICTURE blocks without decoding audio or loading the whole song.
public enum FLACArtwork {
    public static func image(in url: URL) throws -> Data? {
        var fallback: Data?
        try FLACMetadataBlocks.read(in: url, including: [6]) { _, block in
            guard let picture = picture(block) else { return true }
            if picture.front { fallback = picture.data; return false }
            if fallback == nil { fallback = picture.data }
            return true
        }
        return fallback
    }

    private static func picture(_ block: Data) -> (data: Data, front: Bool)? {
        var offset = 0
        func integer() -> Int? {
            guard offset <= block.count - 4 else { return nil }
            let value = block[offset..<(offset + 4)].reduce(0) { ($0 << 8) | Int($1) }
            offset += 4
            return value
        }
        func bytes(_ count: Int) -> Data? {
            guard count >= 0, count <= block.count - offset else { return nil }
            defer { offset += count }
            return block.subdata(in: offset..<(offset + count))
        }
        guard let type = integer(), let mimeLength = integer(), let mime = bytes(mimeLength),
            mime != Data("-->".utf8), let descriptionLength = integer(), bytes(descriptionLength) != nil,
            integer() != nil, integer() != nil, integer() != nil, integer() != nil,
            let length = integer(), length > 0, let data = bytes(length)
        else { return nil }
        return (data, type == 3)
    }
}
