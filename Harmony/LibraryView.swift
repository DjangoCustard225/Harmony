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
    var body: some View {
        @Bindable var store = store
        ScrollView {
            content.padding(.horizontal, 16).padding(.vertical, 12).readingWidth()
                .background { NativeScrollToTop().frame(width: 0, height: 0) }
        }
        .navigationTitle(category.title)
        .toolbar {
            if category == .albums {
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
            if category == .songs {
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
            if !albums.isEmpty {
                AlbumGrid(albums: albums)
            } else {
                empty(
                    "No albums yet", symbol: "square.stack",
                    message: "Import music from Files in Settings.")
            }
        case .artists:
            if store.artists.isEmpty {
                empty("No artists yet", symbol: "person.2", message: "Import music from Files to browse its artists.")
            } else {
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
            }
        case .songs:
            if songs.isEmpty {
                empty(
                    "No songs yet", symbol: "music.note",
                    message: "Import music from Files in Settings.")
            } else {
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
    }

    private func empty(_ title: String, symbol: String, message: String) -> some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(message)).padding(.vertical, 24)
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
