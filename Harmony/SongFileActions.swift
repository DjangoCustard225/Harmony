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
        if let url = try? store.library?.fileURL(song.id) {
            ShareLink(item: url) { Label("Share audio file", systemImage: "square.and.arrow.up") }
        }
        Button("Remove from Harmony", systemImage: "trash", role: .destructive) { store.removeSong(song) }
    }
}
