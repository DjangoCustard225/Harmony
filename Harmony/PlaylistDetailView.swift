import SwiftUI
import HarmonyCore

/// Laid out like `AlbumDetailView`: full-bleed cover, centered heading, play button, numbered tracks.
struct PlaylistDetailView: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    private var player: PlayerStore { store.player }
    let playlistID: String
    @State private var renaming: Playlist?
    @State private var confirmingDelete = false
    @State private var addingSongs = false
    @State private var editing = false

    private var playlist: Playlist? { store.playlist(playlistID) }

    var body: some View {
        if let playlist {
            content(playlist, entries: store.entries(in: playlist))
        } else {
            ContentUnavailableView("Playlist deleted", systemImage: "music.note.list").pageBackground()
        }
    }

    private func content(_ playlist: Playlist, entries: [PlaylistEntry]) -> some View {
        let songs = entries.map(\.song)
        return ScrollView {
            VStack(spacing: 0) {
                ArtworkHeaderView(id: nil, mosaic: store.playlistCovers(songs))
                VStack(spacing: 24) {
                    heading(playlist)
                    playButton(playlist, songs: songs)
                    if entries.isEmpty { emptyPlaylist } else { trackList(playlist, entries: entries) }
                }.padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 28)
            }.frame(maxWidth: 640).frame(maxWidth: .infinity)
                .background { NativeScrollToTop().frame(width: 0, height: 0) }
        }
        .ignoresSafeArea(.container, edges: .top)
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .pageBackground()
        .modifier(ArtworkScrollEdges())
        .tint(.white)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { actions(playlist, songs: songs) }
        }
        .sheet(isPresented: $addingSongs) { PlaylistSongPicker(playlist: playlist) }
        .sheet(isPresented: $editing) { PlaylistEditor(playlistID: playlist.id) }
        .playlistNameAlert(
            "Rename Playlist", item: $renaming, initialName: { $0.name }, confirmTitle: "Save"
        ) { playlist, name in
            store.renamePlaylist(playlist, to: name)
        }
        .confirmationDialog(
            "Delete “\(playlist.name)”?", isPresented: $confirmingDelete, titleVisibility: .visible
        ) {
            Button("Delete Playlist", role: .destructive) {
                store.deletePlaylist(playlist)
                dismiss()
            }
        } message: {
            Text("The songs stay in your library.")
        }
    }

    private func heading(_ playlist: Playlist) -> some View {
        VStack(spacing: 8) {
            Text(playlist.name).font(.title2.weight(.bold)).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
            Text("Updated \(playlist.modified.formatted(date: .abbreviated, time: .omitted))")
                .font(.subheadline.weight(.medium)).foregroundStyle(theme.secondary)
        }.multilineTextAlignment(.center).frame(maxWidth: .infinity)
    }

    private func playButton(_ playlist: Playlist, songs: [Song]) -> some View {
        HStack {
            Spacer(minLength: 0)
            Button {
                store.playPlaylist(playlist)
            } label: {
                Image(systemName: "play.fill").font(.system(size: 24, weight: .semibold))
                    .offset(x: 2).frame(width: 44, height: 44)
            }.buttonStyle(.glass).controlSize(.large).buttonBorderShape(.circle)
                .foregroundStyle(.white).disabled(songs.isEmpty)
                .accessibilityLabel("Play playlist").accessibilityHint("Play songs in playlist order")
            Spacer(minLength: 0)
        }
    }

    private func trackList(_ playlist: Playlist, entries: [PlaylistEntry]) -> some View {
        let songs = entries.map(\.song)
        return LazyVStack(alignment: .leading, spacing: 0) {
            Divider().overlay(theme.border)
            ForEach(Array(entries.enumerated()), id: \.element.position) { index, entry in
                VStack(alignment: .leading, spacing: 0) {
                    AlbumTrackRow(song: entry.song, number: index + 1, showArtist: true) {
                        store.removeFromPlaylist(playlist, at: IndexSet(integer: index), entries: entries)
                    } action: {
                        player.play(songs, at: index)
                    }
                    Divider().overlay(theme.border).padding(.leading, 34)
                }
            }
            Text(PlaylistSummary.text(songs)).font(.caption).foregroundStyle(theme.secondary).padding(.top, 20)
        }
    }

    private func actions(_ playlist: Playlist, songs: [Song]) -> some View {
        Menu {
            Section {
                Button("Play", systemImage: "play.fill") { store.playPlaylist(playlist) }
                Button("Shuffle", systemImage: "shuffle") { store.playPlaylist(playlist, shuffle: true) }
                Button("Play next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                    if player.current == nil {
                        player.play(songs)
                    } else {
                        songs.reversed().forEach { player.add($0, next: true) }
                    }
                }
                Button("Add to queue", systemImage: "text.badge.plus") {
                    songs.forEach { player.add($0, next: false) }
                }
            }.disabled(songs.isEmpty)
            Section {
                Button("Add Songs", systemImage: "plus") { addingSongs = true }
                Button("Edit Order", systemImage: "arrow.up.arrow.down") { editing = true }
                    .disabled(songs.isEmpty)
                Button("Rename", systemImage: "pencil") { renaming = playlist }
                Button("Delete Playlist", systemImage: "trash", role: .destructive) { confirmingDelete = true }
            }
        } label: {
            Image(systemName: "ellipsis").foregroundStyle(.white)
        }
        .accessibilityLabel("Playlist actions")
    }

    private var emptyPlaylist: some View {
        ContentUnavailableView {
            Label("No songs yet", systemImage: "music.note")
        } description: {
            Text(
                store.songs.isEmpty
                    ? "Import music first, then add songs here."
                    : "Add songs here, or choose Add to Playlist from any song’s menu.")
        } actions: {
            if !store.songs.isEmpty {
                Button("Add Songs", systemImage: "plus") { addingSongs = true }
                    .buttonStyle(.glass).controlSize(.large)
            }
        }
    }
}

/// Reorders and removes playlist songs with list drag handles.
private struct PlaylistEditor: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let playlistID: String

    var body: some View {
        NavigationStack {
            Group {
                if let playlist = store.playlist(playlistID) {
                    let entries = store.entries(in: playlist)
                    List {
                        ForEach(entries, id: \.position) { entry in
                            HStack(spacing: 10) {
                                ArtworkView(id: entry.song.coverArt, size: 192).frame(width: 40, height: 40)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.song.title).font(.subheadline.weight(.medium)).lineLimit(1)
                                    Text(entry.song.artistName).font(.caption).foregroundStyle(theme.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .listRowBackground(Color.clear)
                        }
                        .onDelete { store.removeFromPlaylist(playlist, at: $0, entries: entries) }
                        .onMove { store.movePlaylistSongs(playlist, from: $0, to: $1, entries: entries) }
                    }
                    .listStyle(.plain)
                    .environment(\.editMode, .constant(.active))
                    .navigationTitle(playlist.name)
                } else {
                    ContentUnavailableView("Playlist deleted", systemImage: "music.note.list")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .pageBackground()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

/// Picks library songs to append to a playlist, in the order they were tapped.
private struct PlaylistSongPicker: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let playlist: Playlist
    @State private var query = ""
    @State private var selected: [String] = []

    private var results: [Song] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return store.songs }
        return store.songs.filter {
            $0.title.localizedStandardContains(term) || $0.artistName.localizedStandardContains(term)
                || ($0.album?.localizedStandardContains(term) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.songs.isEmpty {
                    ContentUnavailableView(
                        "No songs yet", systemImage: "music.note",
                        description: Text("Import music from the Albums or Songs tab first."))
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(results) { song in row(song) }.listStyle(.plain)
                }
            }
            .searchable(text: $query, prompt: "Songs, artists, albums")
            .navigationTitle("Add to “\(playlist.name)”").navigationBarTitleDisplayMode(.inline)
            .pageBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selected.isEmpty ? "Add" : "Add \(selected.count)") {
                        let byID = Dictionary(store.songs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                        store.addToPlaylist(selected.compactMap { byID[$0] }, playlist)
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
    }

    private func row(_ song: Song) -> some View {
        let isSelected = selected.contains(song.id)
        return Button {
            if isSelected { selected.removeAll { $0 == song.id } } else { selected.append(song.id) }
        } label: {
            HStack(spacing: 10) {
                ArtworkView(id: song.coverArt, size: 192).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(song.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                    Text(song.artistName).font(.caption).foregroundStyle(theme.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(isSelected ? theme.accent : theme.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
