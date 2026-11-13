import Foundation

/// A folder the user linked (for example in iCloud Drive). Its songs play from where they are and
/// are never copied into, or deleted by, Harmony.
public struct LinkedFolder: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String
    /// Security-scoped bookmark that reopens the folder on later launches.
    public var bookmark: Data
    public let added: Date
    public var lastScan: Date?
    /// Paths the user removed from Harmony; rescans leave them out until they're shown again.
    public var hidden: [String]

    public init(
        id: String = UUID().uuidString, name: String, bookmark: Data, added: Date = Date(), lastScan: Date? = nil,
        hidden: [String] = []
    ) {
        self.id = id
        self.name = name
        self.bookmark = bookmark
        self.added = added
        self.lastScan = lastScan
        self.hidden = hidden
    }

    private enum CodingKeys: String, CodingKey { case id, name, bookmark, added, lastScan, hidden }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        bookmark = try container.decode(Data.self, forKey: .bookmark)
        added = try container.decode(Date.self, forKey: .added)
        lastScan = try container.decodeIfPresent(Date.self, forKey: .lastScan)
        hidden = try container.decodeIfPresent([String].self, forKey: .hidden) ?? []
    }
}

/// How a linked folder's contents differ from the index. Pure, so it's tested on Linux.
public struct LinkedFolderChanges: Equatable, Sendable {
    /// Paths in the folder that aren't indexed or hidden, in scan order.
    public var added: [String]
    /// Indexed songs whose files are no longer at their paths. Some may turn out to be moves.
    public var missing: [LocalTrack]

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.added == rhs.added && lhs.missing.map(\.id) == rhs.missing.map(\.id)
    }

    public init(folderID: String, scanned: [String], index: LocalLibraryIndex) {
        let hidden = Set(index.folder(folderID)?.hidden ?? [])
        let indexed = index.tracks(inFolder: folderID)
        let known = Set(indexed.map(\.filename))
        let present = Set(scanned)
        var seen = Set<String>()
        added = scanned.filter { !known.contains($0) && !hidden.contains($0) && seen.insert($0).inserted }
        missing = indexed.filter { !present.contains($0.filename) }
    }

    /// The missing song a new file is a moved or renamed copy of, matched by content.
    public static func moveSource(for fingerprint: FileFingerprint, among missing: [LocalTrack]) -> LocalTrack? {
        missing.first { $0.fingerprint?.size == fingerprint.size && $0.fingerprint?.sha256 == fingerprint.sha256 }
    }
}
