import SwiftUI
import HarmonyCore

extension LibraryTab {
    var symbol: String {
        switch self {
        case .albums: "square.stack"
        case .artists: "person.2"
        case .songs: "music.note"
        case .playlists: "music.note.list"
        }
    }
}

extension TabLayout {
    static let storageKey = "tabLayout"
}

/// Shows, hides and reorders the tab bar's tabs.
struct TabSettingsView: View {
    @Environment(\.appTheme) private var theme
    @AppStorage(TabLayout.storageKey) private var storage = TabLayout.standard.storage

    var body: some View {
        let layout = TabLayout(storage: storage)
        List {
            Section {
                ForEach(layout.order, id: \.self) { tab in row(tab, layout: layout) }
                    .onMove { offsets, destination in
                        var changed = layout
                        changed.move(from: offsets, to: destination)
                        storage = changed.storage
                    }
            } footer: {
                Text(footer(layout))
            }
            .listRowBackground(theme.surface)
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Tabs").navigationBarTitleDisplayMode(.inline)
        .pageBackground()
    }

    private func row(_ tab: LibraryTab, layout: TabLayout) -> some View {
        let isVisible = layout.isVisible(tab)
        return Button {
            var changed = layout
            changed.toggle(tab)
            storage = changed.storage
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isVisible ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(isVisible ? theme.accent : theme.secondary)
                Label(tab.title, systemImage: tab.symbol).foregroundStyle(.primary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!layout.canToggle(tab))
        .accessibilityAddTraits(isVisible ? .isSelected : [])
    }

    private func footer(_ layout: TabLayout) -> String {
        "Show up to \(TabLayout.maxVisible) tabs. Settings and Search are always shown. Drag to reorder."
    }
}

extension View {
    /// Presents the import picker for `AppStore.importMode`.
    func musicImporter() -> some View {
        modifier(MusicImporter())
    }
}

private struct MusicImporter: ViewModifier {
    @Environment(AppStore.self) private var store

    func body(content: Content) -> some View {
        @Bindable var store = store
        content.sheet(item: $store.importMode) { mode in
            MusicFilePicker(mode: mode) { urls in
                store.importMode = nil
                Task {
                    switch mode {
                    case .files: await store.importFiles(urls)
                    case .folder: if let url = urls.first { await store.importFolder(url) }
                    case .link: if let url = urls.first { await store.linkFolder(url) }
                    }
                }
            } onCancel: {
                store.importMode = nil
                store.reconnectingFolderID = nil
            }
        }
    }
}
