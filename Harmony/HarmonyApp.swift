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
}

struct RootView: View {
    @Environment(AppStore.self) private var store
    @EnvironmentObject private var interface: PlaybackInterfaceState
    @EnvironmentObject private var appearance: ArtworkAppearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
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

    private var appContent: some View {
        TabView(selection: $selection) {
            Tab("Library", systemImage: "music.note.square.stack", value: AppTab.library) {
                AlbumNavigationStack { LibraryHomeView() }
            }
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                NavigationStack { SettingsView() }
            }
            Tab("Search", systemImage: "magnifyingglass", value: .search, role: .search) {
                AlbumNavigationStack { MusicSearchView(query: $searchQuery) }
                    .searchable(
                        text: $searchQuery, isPresented: $searchPresented, prompt: "Albums, artists, tracks"
                    )
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
