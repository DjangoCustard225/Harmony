import SwiftUI
import HarmonyCore

struct MusicSearchView: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppStore.self) private var store
    private var player: PlayerStore { store.player }
    @Binding var query: String
    @State private var results = SearchResults()
    @State private var filter = SearchFilter.all
    @State private var loading = false
    private var term: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private enum SearchFilter: String, CaseIterable {
        case all = "All", albums = "Albums", artists = "Artists", songs = "Tracks"
    }

    var body: some View {
        Group {
            if store.songs.isEmpty {
                LibraryEmptyState(
                    title: "Nothing to search", symbol: "magnifyingglass",
                    message: "Import music to search your albums, artists and tracks.")
            } else if term.isEmpty {
                ContentUnavailableView(
                    "Search your library", systemImage: "magnifyingglass",
                    description: Text("Find albums, artists and tracks."))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Picker("Search filter", selection: $filter) {
                            ForEach(SearchFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented)
                        if !results.isEmpty { resultContent }
                        if loading {
                            ProgressView().accessibilityLabel("Searching").frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                        } else if visibleResultsEmpty {
                            ContentUnavailableView.search(text: term).padding(.top, 24)
                        }
                    }.padding(16).readingWidth()
                        .background { NativeScrollToTop().frame(width: 0, height: 0) }
                }
            }
        }
        .navigationTitle("Search").pageBackground()
        // Searching again after a library change drops removed songs from the results.
        .task(id: "\(store.sessionID):\(term)") {
            results = SearchResults()
            loading = !term.isEmpty
            guard !term.isEmpty else { return }
            do {
                try await Task.sleep(for: .milliseconds(350))
                try Task.checkCancellation()
                results = store.library?.index.search(term) ?? SearchResults()
                loading = false
            } catch { /* A newer query owns the search state after cancellation. */  }
        }
    }

    private var visibleResultsEmpty: Bool {
        switch filter {
        case .all: results.isEmpty
        case .albums: results.albums.isEmpty
        case .artists: results.artists.isEmpty
        case .songs: results.songs.isEmpty
        }
    }
    @ViewBuilder private var resultContent: some View {
        if (filter == .all || filter == .albums) && !results.albums.isEmpty {
            if filter == .all { SectionTitle(title: "Albums") }
            AlbumGrid(albums: results.albums)
        }
        if (filter == .all || filter == .artists) && !results.artists.isEmpty {
            if filter == .all { SectionTitle(title: "Artists") }
            LazyVStack(spacing: 0) {
                ForEach(results.artists) { artist in
                    NavigationLink {
                        ArtistDetailView(artist: artist)
                    } label: {
                        ArtistRow(artist: artist)
                    }.buttonStyle(.plain)
                }
            }
        }
        if (filter == .all || filter == .songs) && !results.songs.isEmpty {
            if filter == .all { SectionTitle(title: "Tracks") }
            LazyVStack(spacing: 0) {
                ForEach(Array(results.songs.enumerated()), id: \.element.id) { index, song in
                    VStack(spacing: 0) {
                        SongRow(song: song) { player.play(results.songs, at: index) }
                        Divider().overlay(theme.border)
                    }
                }
            }
        }
    }
}
