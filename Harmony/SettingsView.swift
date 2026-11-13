import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appTheme) private var theme
    @AppStorage("artistDetailsEnabled") private var artistDetails = true

    var body: some View {
        List {
            Section("Music") {
                Button("Import music", systemImage: "plus") {
                    store.importMode = .files
                }
                .disabled(store.libraryBusy)
                Button {
                    Task { await store.refreshLibraryFromDisk() }
                } label: {
                    HStack {
                        Label("Refresh library", systemImage: "arrow.clockwise")
                        Spacer()
                        if store.refreshingLibrary { ProgressView() }
                    }
                }.disabled(store.libraryBusy)
                Button {
                    Task { await store.refreshImportedMetadata(force: true) }
                } label: {
                    HStack {
                        Label("Refresh metadata", systemImage: "arrow.clockwise")
                        Spacer()
                        if store.refreshingMetadata { ProgressView() }
                    }
                }.disabled(store.libraryBusy)
                NavigationLink {
                    MusicFoldersView()
                } label: {
                    Label("Music folders", systemImage: "folder")
                }
                NavigationLink {
                    DuplicateReviewView()
                } label: {
                    Label("Review duplicates", systemImage: "square.on.square")
                }.disabled(store.libraryBusy)
                if store.importing || store.refreshingLibrary {
                    HStack {
                        ProgressView(); Text(store.importProgress).foregroundStyle(theme.secondary)
                    }
                }
            }.listRowBackground(theme.surface)

            Section {
                NavigationLink {
                    TabSettingsView()
                } label: {
                    Label("Tabs", systemImage: "dock.rectangle")
                }
                Toggle("Fetch artist info", isOn: $artistDetails).tint(theme.switchTint)
            }.listRowBackground(theme.surface)
        }
        .listSectionSpacing(.compact).navigationTitle("Settings").pageBackground()
    }
}
