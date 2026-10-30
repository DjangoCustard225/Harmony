import SwiftUI
import HarmonyCore

struct ArtistPortraitView: View {
    @Environment(AppStore.self) private var store
    @AppStorage("artistDetailsEnabled") private var enabled = true
    let artist: Artist
    var cornerRadius: CGFloat = 0
    @State private var image: UIImage?

    var body: some View {
        Color.clear.aspectRatio(1, contentMode: .fit)
            .overlay {
                if enabled, let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    ZStack {
                        Color.white.opacity(0.06)
                        Image(systemName: "person.fill").resizable().scaledToFit()
                            .foregroundStyle(.white.opacity(0.25)).padding(24)
                    }
                }
            }.clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .task(id: "\(artist.id):\(store.artistProfiles.revision):\(enabled)") {
                guard enabled else { image = nil; return }
                let profile = await store.artistProfiles.load(artist, musicBrainzID: store.musicBrainzID(for: artist))
                guard !Task.isCancelled else { return }
                if let profile { image = await store.artistProfiles.photo(profile) } else { image = nil }
            }.accessibilityHidden(true)
    }
}
