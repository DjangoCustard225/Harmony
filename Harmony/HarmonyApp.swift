import SwiftUI
import HarmonyCore

@main
struct HarmonyApp: App {
    @State private var store = AppStore()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environmentObject(store.player)
                .environmentObject(store.player.interface)
                .environmentObject(store.appearance)
                .preferredColorScheme(.dark)
        }
    }
}

private enum AppTab: Hashable {
    case library, settings, search
    // Sidebar destinations on iPad.
    case recent, artists, albums, songs, playlists
    case playlist(String)
}

struct RootView: View {
    @Environment(AppStore.self) private var store
    @EnvironmentObject private var interface: PlaybackInterfaceState
    @EnvironmentObject private var appearance: ArtworkAppearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selection = AppTab.library
    @State private var searchQuery = ""
    @State private var searchPresented = false

    var body: some View {
        @Bindable var store = store
        appContent
            .musicImporter()
            .task {
                await store.library?.openLinkedFolders()
                await store.refreshImportedMetadata()
                await store.rescanLinkedFolders()
            }
            // Pick up files added to linked folders (for example in iCloud Drive) while away.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await store.rescanLinkedFolders() } }
            }
            .onOpenURL { url in Task { await store.importFiles([url]) } }
            .overlay(alignment: .top) {
                if store.importing {
                    HStack {
                        ProgressView(); Text(store.importProgress)
                    }
                    .padding().glassEffect().padding(.top, 8)
                }
            }
            .background {
                PlayerPresentation(store: store, isPresented: interface.expanded, reduceMotion: reduceMotion)
            }
            .allowsHitTesting(!interface.expanded)
            .accessibilityHidden(interface.expanded)
            .background(AppBackground())
            .alert(
                "Harmony", isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })
            ) {
                Button("OK", role: .cancel) { store.notice = nil }
            } message: {
                Text(store.notice ?? "")
            }
            // Song menus inside the player's queue sheet present their own prompt.
            .newPlaylistPrompt(isActive: !interface.expanded)
            .environment(\.appTheme, appearance.theme.oled)
            .tint(appearance.theme.accent)
            .task(id: "\(interface.expanded):\(store.sessionID):\(interface.current?.coverArt ?? "")") {
                guard !interface.expanded else { return }
                await appearance.update(
                    coverArt: interface.current?.coverArt, library: store.library, cache: store.artwork,
                    reduceMotion: reduceMotion)
            }
    }

    @ViewBuilder private var appContent: some View {
        Group {
            if sizeClass == .regular { sidebarTabs } else { compactTabs }
        }
        .tabViewSearchActivation(.searchTabSelection)
        .onChange(of: selection) { _, tab in
            if tab != .search { searchPresented = false }
        }
        .onChange(of: sizeClass, initial: true) { _, size in selection = adapted(selection, to: size) }
        // A deleted playlist can't stay selected in the sidebar.
        .onChange(of: store.playlists) { _, playlists in
            if case .playlist(let id) = selection, !playlists.contains(where: { $0.id == id }) {
                selection = .playlists
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory(isEnabled: interface.current != nil) {
            MiniPlayer()
        }
    }

    /// iPhone: Library, Settings and Search in a tab bar.
    private var compactTabs: some View {
        TabView(selection: $selection) {
            Tab("Library", systemImage: "music.note.square.stack", value: AppTab.library) {
                AlbumNavigationStack { LibraryHomeView() }
            }
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                NavigationStack { SettingsView() }
            }
            Tab("Search", systemImage: "magnifyingglass", value: .search, role: .search) { searchContent }
        }
    }

    /// iPad: a sidebar with each part of the library and every playlist, like Music.
    private var sidebarTabs: some View {
        TabView(selection: $selection) {
            Tab("Search", systemImage: "magnifyingglass", value: AppTab.search, role: .search) { searchContent }
            TabSection("Library") {
                Tab("Recently Added", systemImage: "clock", value: AppTab.recent) {
                    AlbumNavigationStack { RecentlyAddedView() }
                }
                Tab("Artists", systemImage: "music.microphone", value: AppTab.artists) {
                    AlbumNavigationStack { LibraryView(category: .artists) }
                }
                Tab("Albums", systemImage: "square.stack", value: AppTab.albums) {
                    AlbumNavigationStack { LibraryView(category: .albums) }
                }
                Tab("Songs", systemImage: "music.note", value: AppTab.songs) {
                    AlbumNavigationStack { LibraryView(category: .songs) }
                }
            }
            TabSection("Playlists") {
                Tab("All Playlists", systemImage: "square.grid.2x2", value: AppTab.playlists) {
                    AlbumNavigationStack { PlaylistsView() }
                }
                ForEach(store.playlists.reversed()) { playlist in
                    Tab(playlist.name, systemImage: "music.note.list", value: AppTab.playlist(playlist.id)) {
                        AlbumNavigationStack { PlaylistDetailView(playlistID: playlist.id) }
                    }
                    .defaultVisibility(.hidden, for: .tabBar)
                }
            }
            .sectionActions {
                Button("New Playlist", systemImage: "plus") { store.newPlaylistRequest = [] }
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                NavigationStack { SettingsView() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }

    private var searchContent: some View {
        AlbumNavigationStack { MusicSearchView(query: $searchQuery) }
            .searchable(text: $searchQuery, isPresented: $searchPresented, prompt: "Albums, artists, tracks")
    }

    /// Keeps the selection meaningful when the layout switches, for example in Split View.
    private func adapted(_ tab: AppTab, to size: UserInterfaceSizeClass?) -> AppTab {
        switch (size, tab) {
        case (.regular, .library): .recent
        case (.regular, _): tab
        case (_, .settings), (_, .search), (_, .library): tab
        default: .library
        }
    }
}
