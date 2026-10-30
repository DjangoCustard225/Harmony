import Foundation

/// Native FLAC STREAMINFO and Vorbis comments (RFC 9639 sections 8.2 and 8.6).
public enum FLACMetadata {
    public static func read(from url: URL) throws -> TrackMetadata? {
        var result = TrackMetadata()
        let isFLAC = try FLACMetadataBlocks.read(in: url, including: [0, 4]) { type, block in
            if type == 4, let comments = comments(in: block) {
                for (key, values) in comments { for value in values { result.append(value, for: key) } }
            } else if type == 0, block.count == 34 {
                let audio = block[10..<18].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
                let rate = Int(audio >> 44)
                result.sampleRate = rate > 0 ? rate : nil
                result.channels = Int((audio >> 41) & 7) + 1
                result.bitsPerSample = Int((audio >> 36) & 31) + 1
                let samples = audio & 0xFFFFFFFFF
                if rate > 0, samples > 0 { result.duration = Double(samples) / Double(rate) }
            }
            return true
        }
        return isFLAC ? result : nil
    }
    private static func comments(in data: Data) -> [String: [String]]? {
        var offset = 0
        func integer() -> Int? {
            guard offset <= data.count - 4 else { return nil }
            let value = (0..<4).reduce(0) { $0 | (Int(data[offset + $1]) << (8 * $1)) }
            offset += 4
            return value
        }
        func field() -> Data? {
            guard let size = integer(), size <= data.count - offset else { return nil }
            defer { offset += size }
            return data.subdata(in: offset..<(offset + size))
        }
        guard field() != nil, let count = integer(), count <= (data.count - offset) / 4 else { return nil }
        var tags: [String: [String]] = [:]
        for _ in 0..<count {
            guard let raw = field() else { return nil }
            guard let text = String(data: raw, encoding: .utf8), let equals = text.firstIndex(of: "=") else { continue }
            let key = String(text[..<equals]).uppercased()
            guard !key.isEmpty else { continue }
            tags[key, default: []].append(String(text[text.index(after: equals)...]))
        }
        return tags
    }
}
