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
                .disabled(store.importing)
                Button {
                    Task { await store.refreshLibraryFromDisk() }
                } label: {
                    HStack {
                        Label("Refresh library", systemImage: "arrow.clockwise")
                        Spacer()
                        if store.refreshingLibrary { ProgressView() }
                    }
                }.disabled(store.importing || store.refreshingLibrary)
                Button {
                    Task { await store.refreshImportedMetadata(force: true) }
                } label: {
                    HStack {
                        Label("Refresh metadata", systemImage: "arrow.clockwise")
                        Spacer()
                        if store.refreshingMetadata { ProgressView() }
                    }
                }.disabled(store.importing || store.refreshingMetadata)
                if store.importing {
                    HStack {
                        ProgressView(); Text(store.importProgress).foregroundStyle(theme.secondary)
                    }
                }
            }.listRowBackground(theme.surface)

            Section {
                Toggle("Artist photos & biographies", isOn: $artistDetails).tint(theme.switchTint)
            }.listRowBackground(theme.surface)
        }.listSectionSpacing(.compact).navigationTitle("Settings").pageBackground()
    }
}
