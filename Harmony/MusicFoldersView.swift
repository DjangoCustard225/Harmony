import SwiftUI
import HarmonyCore

/// Folders whose songs Harmony plays in place, such as a music folder in iCloud Drive.
struct MusicFoldersView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appTheme) private var theme
    @State private var unlinking: LinkedFolder?

    var body: some View {
        List {
            Section {
                ForEach(store.linkedFolders) { folder in row(folder) }
                Button("Link Folder…", systemImage: "folder.badge.plus") {
                    store.reconnectingFolderID = nil
                    store.importMode = .link
                }
                .disabled(store.libraryBusy)
            } footer: {
                Text(
                    "Songs in a linked folder play from where they are, so nothing is copied into Harmony. "
                        + "New, moved and deleted files are picked up when you open Harmony. "
                        + "For iCloud Drive, choose Keep Downloaded on the folder in Files so songs play offline. "
                        + "Harmony never changes or deletes files in a linked folder.")
            }
            .listRowBackground(theme.surface)
            if store.importing || store.refreshingLibrary {
                Section {
                    HStack {
                        ProgressView(); Text(store.importProgress).foregroundStyle(theme.secondary)
                    }
                }.listRowBackground(theme.surface)
            }
        }
        .navigationTitle("Music Folders").navigationBarTitleDisplayMode(.inline)
        .pageBackground()
        .confirmationDialog(
            "Unlink “\(unlinking?.name ?? "")”?",
            isPresented: Binding(get: { unlinking != nil }, set: { if !$0 { unlinking = nil } }),
            titleVisibility: .visible, presenting: unlinking
        ) { folder in
            Button("Unlink Folder", role: .destructive) { store.unlinkFolder(folder.id) }
        } message: { _ in
            Text("Its songs are removed from Harmony and from your playlists. The files stay in the folder.")
        }
    }

    private func row(_ folder: LinkedFolder) -> some View {
        let available = store.isFolderAvailable(folder.id)
        let count = store.songCount(inFolder: folder.id)
        return Menu {
            if available {
                Button("Rescan", systemImage: "arrow.clockwise") { Task { await store.rescanFolder(folder.id) } }
            } else {
                Button("Reconnect…", systemImage: "link") {
                    store.reconnectingFolderID = folder.id
                    store.importMode = .link
                }
            }
            if !folder.hidden.isEmpty {
                Button(
                    "Show \(folder.hidden.count) Removed \(folder.hidden.count == 1 ? "Song" : "Songs")",
                    systemImage: "eye"
                ) {
                    Task { await store.showHiddenSongs(inFolder: folder.id) }
                }
            }
            Button("Unlink", systemImage: "folder.badge.minus", role: .destructive) { unlinking = folder }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: available ? "folder.fill" : "exclamationmark.triangle.fill")
                    .font(.title2).foregroundStyle(available ? theme.accent : .orange).frame(width: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(folder.name).font(.body.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                    Text(detail(folder, count: count, available: available))
                        .font(.caption).foregroundStyle(theme.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "ellipsis").foregroundStyle(theme.secondary)
            }
            .contentShape(Rectangle())
        }
        .disabled(store.libraryBusy)
        .accessibilityHint("Folder actions")
    }

    private func detail(_ folder: LinkedFolder, count: Int, available: Bool) -> String {
        guard available else { return "Can’t be opened. Tap to reconnect it." }
        var parts = ["\(count) \(count == 1 ? "song" : "songs")"]
        if let scanned = folder.lastScan {
            parts.append("scanned \(scanned.formatted(.relative(presentation: .named)))")
        }
        return parts.joined(separator: " · ")
    }
}
