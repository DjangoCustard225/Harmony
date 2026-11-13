import Foundation

/// A tab the user can show or hide. Settings and Search are always shown and are not listed here.
public enum LibraryTab: String, CaseIterable, Hashable, Sendable {
    case albums, artists, songs, playlists

    public var title: String { rawValue.capitalized }
}

/// Which tabs appear in the tab bar, and in what order.
///
/// iPhone fits five tabs and Settings and Search always take two, so at most `maxVisible` are
/// shown and at least one always is. Every initializer normalizes its input, so a layout is always valid.
public struct TabLayout: Equatable, Sendable {
    public static let maxVisible = 3
    public static let standard = TabLayout(
        order: LibraryTab.allCases, visible: [.albums, .songs, .playlists])

    /// Every tab, visible or not, in the user's order.
    public private(set) var order: [LibraryTab]
    public private(set) var visible: Set<LibraryTab>

    public init(order: [LibraryTab], visible: Set<LibraryTab>) {
        var seen = Set<LibraryTab>()
        var tabs = order.filter { seen.insert($0).inserted }
        tabs += LibraryTab.allCases.filter { !seen.contains($0) }
        self.order = tabs
        var shown = tabs.filter(visible.contains)
        if shown.isEmpty { shown = [tabs[0]] }
        self.visible = Set(shown.prefix(Self.maxVisible))
    }

    /// Reads `storage`, falling back to `standard` for anything unreadable.
    public init(storage: String) {
        var order: [LibraryTab] = []
        var visible = Set<LibraryTab>()
        for item in storage.split(separator: ",") {
            let hidden = item.hasPrefix("-")
            guard let tab = LibraryTab(rawValue: String(hidden ? item.dropFirst() : item)) else { continue }
            order.append(tab)
            if !hidden { visible.insert(tab) }
        }
        self = order.isEmpty ? .standard : TabLayout(order: order, visible: visible)
    }

    /// Comma-separated tabs in order, with hidden ones prefixed by "-".
    public var storage: String {
        order.map { visible.contains($0) ? $0.rawValue : "-\($0.rawValue)" }.joined(separator: ",")
    }

    public var visibleTabs: [LibraryTab] { order.filter(visible.contains) }

    public func isVisible(_ tab: LibraryTab) -> Bool { visible.contains(tab) }

    /// Whether tapping `tab` would change it: the last visible tab can't be hidden, and a hidden
    /// tab can't be shown once `maxVisible` are.
    public func canToggle(_ tab: LibraryTab) -> Bool {
        visible.contains(tab) ? visible.count > 1 : visible.count < Self.maxVisible
    }

    public mutating func toggle(_ tab: LibraryTab) {
        guard canToggle(tab) else { return }
        if visible.contains(tab) { visible.remove(tab) } else { visible.insert(tab) }
    }

    /// Same meaning as SwiftUI `onMove`: `destination` is an index before the move.
    public mutating func move(from offsets: IndexSet, to destination: Int) {
        let valid = offsets.filter { order.indices.contains($0) }
        guard !valid.isEmpty else { return }
        let moving = valid.map { order[$0] }
        let target = min(max(0, destination), order.count)
        let shift = valid.filter { $0 < target }.count
        for offset in valid.sorted(by: >) { order.remove(at: offset) }
        order.insert(contentsOf: moving, at: target - shift)
    }
}
