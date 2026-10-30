import SwiftUI

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

private enum AppTab: Hashable { case albums, artists, songs, search, settings }

struct RootView: View {
    @Environment(AppStore.self) private var store
    @EnvironmentObject private var interface: PlaybackInterfaceState
    @EnvironmentObject private var appearance: ArtworkAppearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection = AppTab.albums
    @State private var searchQuery = ""
    @State private var searchPresented = false

    var body: some View {
        @Bindable var store = store
        appContent
            .sheet(item: $store.importMode) { mode in
                MusicFilePicker(mode: mode) { urls in
                    store.importMode = nil
                    Task {
                        await store.importFiles(urls)
                    }
                } onCancel: {
                    store.importMode = nil
                }
            }
            .task { await store.refreshImportedMetadata() }
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
            .environment(\.appTheme, appearance.theme.oled)
            .tint(appearance.theme.accent)
            .onChange(of: store.sessionID) { _, _ in
                searchPresented = false; searchQuery = ""; selection = .albums
            }
            .task(id: "\(interface.expanded):\(store.sessionID):\(interface.current?.coverArt ?? "")") {
                guard !interface.expanded else { return }
                await appearance.update(
                    coverArt: interface.current?.coverArt, library: store.library, cache: store.artwork,
                    reduceMotion: reduceMotion)
            }
    }

    private var appContent: some View {
        TabView(selection: $selection) {
            Tab("Albums", systemImage: "square.stack", value: .albums) {
                NavigationStack { LibraryView(category: .albums) }.id(store.sessionID)
            }
            Tab("Artists", systemImage: "person.2", value: .artists) {
                NavigationStack { LibraryView(category: .artists) }.id(store.sessionID)
            }
            Tab("Songs", systemImage: "music.note", value: .songs) {
                NavigationStack { LibraryView(category: .songs) }.id(store.sessionID)
            }
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                NavigationStack { SettingsView() }
            }
            Tab("Search", systemImage: "magnifyingglass", value: .search, role: .search) {
                NavigationStack { MusicSearchView(query: $searchQuery) }
                    .searchable(
                        text: $searchQuery, isPresented: $searchPresented, prompt: "Albums, artists, tracks"
                    )
                    .id(store.sessionID)
            }
        }
        .tabViewSearchActivation(.searchTabSelection)
        .onChange(of: selection) { _, tab in
            if tab != .search { searchPresented = false }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory(isEnabled: interface.current != nil) {
            MiniPlayer()
        }
    }
}
