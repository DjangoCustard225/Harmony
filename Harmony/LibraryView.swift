import SwiftUI
import HarmonyCore

enum LibraryCategory: String {
    case albums, artists, songs
    var title: String { rawValue.capitalized }
}

struct LibraryView: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppStore.self) private var store
    private var player: PlayerStore { store.player }
    let category: LibraryCategory
    private var albums: [Album] { store.albums }
    private var songs: [Song] { store.songs }
    private var isEmpty: Bool {
        switch category {
        case .albums: albums.isEmpty
        case .artists: store.artists.isEmpty
        case .songs: songs.isEmpty
        }
    }
    var body: some View {
        @Bindable var store = store
        Group {
            if isEmpty {
                emptyState
            } else {
                ScrollView {
                    content.padding(.horizontal, 16).padding(.vertical, 12).readingWidth()
                        .background { NativeScrollToTop().frame(width: 0, height: 0) }
                }
            }
        }
        .navigationTitle(category.title)
        .toolbar {
            // Sorting has nothing to act on in an empty library.
            if category == .albums && !isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort albums", selection: $store.albumOrder) {
                            Text("A–Z").tag(AlbumOrder.alphabeticalByName)
                            Text("Recently added").tag(AlbumOrder.newest)
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel("Sort albums")
                }
            }
            if category == .songs && !isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Section("Sort by") {
                            Picker("Sort songs", selection: $store.songOrder) {
                                ForEach(SongSortOrder.allCases) { order in Text(order.title).tag(order) }
                            }
                        }
                        Section("Order") {
                            Picker("Sort direction", selection: $store.songSortReversed) {
                                Text(store.songOrder.forwardLabel).tag(false)
                                Text(store.songOrder.reverseLabel).tag(true)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }.accessibilityLabel("Sort songs")
                }
            }
        }
        .pageBackground()
    }

    @ViewBuilder private var content: some View {
        switch category {
        case .albums:
            AlbumGrid(albums: albums)
        case .artists:
            LazyVStack(spacing: 0) {
                ForEach(store.artists) { artist in
                    VStack(spacing: 0) {
                        NavigationLink {
                            ArtistDetailView(artist: artist)
                        } label: {
                            ArtistRow(artist: artist)
                        }.buttonStyle(.plain)
                        Divider().overlay(theme.border).padding(.leading, 74)
                    }
                }
            }
        case .songs:
            LazyVStack(spacing: 0) {
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    VStack(spacing: 0) {
                        SongRow(song: song) { player.play(songs, at: index) }
                        Divider().overlay(theme.border).padding(.leading, 66)
                    }
                }
            }
        }
    }

    @ViewBuilder private var emptyState: some View {
        switch category {
        case .albums:
            LibraryEmptyState(
                title: "No albums yet", symbol: "square.stack",
                message: "Import songs from Files and they’ll appear here, grouped by album.")
        case .artists:
            LibraryEmptyState(
                title: "No artists yet", symbol: "person.2",
                message: "Artists appear here once you import their music.")
        case .songs:
            LibraryEmptyState(
                title: "No songs yet", symbol: "music.note",
                message: "Import songs from Files to start listening.")
        }
    }
}

struct ArtistRow: View {
    @Environment(\.appTheme) private var theme
    let artist: Artist
    var body: some View {
        HStack(spacing: 10) {
            ArtistPortraitView(artist: artist, cornerRadius: 32)
                .frame(width: 64, height: 64).clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(artist.name).font(.headline).foregroundStyle(.white)
                if let count = artist.albumCount {
                    Text("\(count) \(count == 1 ? "album" : "albums")").font(.caption).foregroundStyle(theme.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(theme.secondary)
        }.padding(.vertical, 4).contentShape(Rectangle())
    }
}
