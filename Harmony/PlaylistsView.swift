import SwiftUI
import HarmonyCore

struct PlaylistsView: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppStore.self) private var store
    @State private var renaming: Playlist?
    @State private var deleting: Playlist?

    /// Newest first, matching the "Add to Playlist" menu.
    private var playlists: [Playlist] { store.playlists.reversed() }

    var body: some View {
        Group {
            if store.library == nil {
                // Shows the "Library unavailable" state.
                LibraryEmptyState(title: "No playlists yet", symbol: "music.note.list", message: "")
            } else if playlists.isEmpty {
                ContentUnavailableView {
                    Label("No playlists yet", systemImage: "music.note.list")
                } description: {
                    Text(
                        store.songs.isEmpty
                            ? "Import music, then gather songs into playlists."
                            : "Create a playlist, then add songs from any song’s menu.")
                } actions: {
                    Button("New Playlist", systemImage: "plus") { store.newPlaylistRequest = [] }
                        .buttonStyle(.glass).controlSize(.large)
                    if store.songs.isEmpty { ImportMusicButton() }
                }
            } else {
                list
            }
        }
        .navigationTitle("Playlists")
        .toolbar {
            if store.library != nil && !playlists.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New Playlist", systemImage: "plus") { store.newPlaylistRequest = [] }
                }
            }
        }
        .pageBackground()
        .playlistNameAlert(
            "Rename Playlist", item: $renaming, initialName: { $0.name }, confirmTitle: "Save"
        ) { playlist, name in
            store.renamePlaylist(playlist, to: name)
        }
        .confirmationDialog(
            "Delete “\(deleting?.name ?? "")”?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible, presenting: deleting
        ) { playlist in
            Button("Delete Playlist", role: .destructive) { store.deletePlaylist(playlist) }
        } message: { _ in
            Text("The songs stay in your library.")
        }
    }

    private var list: some View {
        List {
            ForEach(playlists) { playlist in
                NavigationLink {
                    PlaylistDetailView(playlistID: playlist.id)
                } label: {
                    PlaylistRow(playlist: playlist)
                }
                .listRowBackground(Color.clear)
                .contextMenu {
                    Button("Play", systemImage: "play.fill") { store.playPlaylist(playlist) }
                    Button("Shuffle", systemImage: "shuffle") { store.playPlaylist(playlist, shuffle: true) }
                    Button("Rename", systemImage: "pencil") { renaming = playlist }
                    Button("Delete", systemImage: "trash", role: .destructive) { deleting = playlist }
                }
                .swipeActions {
                    Button("Delete", systemImage: "trash", role: .destructive) { deleting = playlist }
                }
            }
        }
        .listStyle(.plain)
    }
}

private struct PlaylistRow: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppStore.self) private var store
    let playlist: Playlist
    var body: some View {
        let songs = store.songs(in: playlist)
        HStack(spacing: 12) {
            ArtworkMosaic(ids: store.playlistCovers(songs), tileSize: 192).frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: Theme.artworkCornerRadius, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(playlist.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
                Text(PlaylistSummary.text(songs)).font(.caption).foregroundStyle(theme.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

enum PlaylistSummary {
    static func text(_ songs: [Song]) -> String {
        guard !songs.isEmpty else { return "Empty" }
        let count = "\(songs.count) \(songs.count == 1 ? "song" : "songs")"
        return "\(count) · \(TimeLabel.duration(songs.reduce(0) { $0 + ($1.duration ?? 0) }))"
    }
}

// MARK: Naming prompts

extension View {
    /// Asks for a playlist name while `item` is set; the field starts with `initialName(item)`.
    func playlistNameAlert<Item>(
        _ title: String, item: Binding<Item?>, initialName: @escaping (Item) -> String, confirmTitle: String,
        action: @escaping (Item, String) -> Void
    ) -> some View {
        modifier(
            PlaylistNameAlert(
                title: title, item: item, initialName: initialName, confirmTitle: confirmTitle, action: action))
    }

    /// Presents the "New Playlist" prompt for `AppStore.newPlaylistRequest`. Attach it once per
    /// presentation layer and pass `isActive: false` where another layer is on screen.
    func newPlaylistPrompt(isActive: Bool = true) -> some View {
        modifier(NewPlaylistPrompt(isActive: isActive))
    }
}

private struct PlaylistNameAlert<Item>: ViewModifier {
    let title: String
    @Binding var item: Item?
    let initialName: (Item) -> String
    let confirmTitle: String
    let action: (Item, String) -> Void
    @State private var name = ""

    func body(content: Content) -> some View {
        content
            .alert(title, isPresented: Binding(get: { item != nil }, set: { if !$0 { item = nil } })) {
                TextField("Playlist name", text: $name)
                Button("Cancel", role: .cancel) { item = nil }
                Button(confirmTitle) {
                    if let item { action(item, name) }
                    item = nil
                }
            }
            .onChange(of: item != nil, initial: true) { _, isSet in
                if isSet, let item { name = initialName(item) }
            }
    }
}

private struct NewPlaylistPrompt: ViewModifier {
    @Environment(AppStore.self) private var store
    let isActive: Bool

    func body(content: Content) -> some View {
        @Bindable var store = store
        content.playlistNameAlert(
            "New Playlist", item: isActive ? $store.newPlaylistRequest : .constant(nil),
            initialName: { _ in "" }, confirmTitle: "Create"
        ) { songs, name in
            store.createPlaylist(name: name, songs: songs)
        }
    }
}
