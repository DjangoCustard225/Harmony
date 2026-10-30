import Foundation

/// Retains every textual tag, including repeated values and fields not used by the library UI.
public struct TrackMetadata: Codable, Sendable {
    public var tags: [String: [String]] = [:]
    public var sampleRate: Int?
    public var channels: Int?
    public var bitsPerSample: Int?
    public var duration: Double?
    public var fileSize: Int64?

    public init(tags: [String: [String]] = [:]) { self.tags = tags }
    public mutating func append(_ value: String, for key: String) {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let key = key.uppercased()
        if !(tags[key] ?? []).contains(value) { tags[key, default: []].append(value) }
    }
    public func values(_ names: String...) -> [String] { values(for: names) }
    private func values(for names: [String]) -> [String] {
        for name in names {
            let key = Self.normalized(name)
            let values = tags.keys.sorted().filter { Self.normalized($0) == key }
                .flatMap { tags[$0] ?? [] }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if !values.isEmpty { return values }
        }
        return []
    }
    public func text(_ names: String...) -> String? {
        let result = values(for: names)
        return result.isEmpty ? nil : result.joined(separator: "; ")
    }
    public func number(_ names: String...) -> Int? {
        values(for: names).first.flatMap {
            Int($0.split(separator: "/").first?.trimmingCharacters(in: .whitespaces) ?? "")
        }
    }
    public var title: String? { text("TITLE") }
    public var artist: String? { text("ARTIST", "PERFORMER") }
    public var albumArtist: String? { text("ALBUMARTIST", "ALBUM ARTIST", "BAND") }
    public var album: String? { text("ALBUM") }
    public var track: Int? { number("TRACKNUMBER", "TRACK") }
    public var disc: Int? { number("DISCNUMBER", "DISC", "DISK") }
    public var year: Int? {
        guard let date = text("DATE", "YEAR", "RELEASEDATE") else { return nil }
        return Int(date.prefix(4))
    }
    public var genre: String? { text("GENRE") }
    public var lyrics: String? { text("SYNCEDLYRICS", "LYRICS", "UNSYNCEDLYRICS", "UNSYNCHRONIZEDLYRICS") }
    private static func normalized(_ value: String) -> String {
        String(value.uppercased().filter { $0.isLetter || $0.isNumber })
    }
}
