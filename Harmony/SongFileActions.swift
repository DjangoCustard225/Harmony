import SwiftUI
import HarmonyCore

struct SongFileActions: View {
    @Environment(AppStore.self) private var store
    let song: Song
    var body: some View {
        NavigationLink {
            TrackInfoView(song: song)
        } label: {
            Label("Track info", systemImage: "info.circle")
        }
        Button("Remove from Harmony", systemImage: "trash", role: .destructive) { store.removeSong(song) }
    }
}
