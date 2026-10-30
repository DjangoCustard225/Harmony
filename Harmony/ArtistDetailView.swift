import SwiftUI
import HarmonyCore

struct ArtistDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appTheme) private var theme
    @AppStorage("artistDetailsEnabled") private var enabled = true
    let artist: Artist
    @State private var loading = true
    @State private var showsAbout = false
    private var albums: [Album] { store.albums.filter { $0.artistId == artist.id } }
    private var profile: ArtistProfile? { enabled ? store.artistProfiles.cached(artist) : nil }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ArtworkHeaderView(id: nil, artist: artist)
                VStack(alignment: .leading, spacing: 24) {
                    Text(artist.name).font(.title2.weight(.bold))
                        .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                        .accessibilityAddTraits(.isHeader)
                    VStack(alignment: .leading, spacing: 12) {
                        if let biography = profile?.biography {
                            Button {
                                showsAbout = true
                            } label: {
                                Text(biography).font(.callout).foregroundStyle(theme.secondary)
                                    .lineSpacing(4).lineLimit(2).multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                                .accessibilityLabel("About \(artist.name)")
                                .accessibilityHint("Open the full artist biography")
                        } else if loading && enabled {
                            HStack {
                                ProgressView(); Text("Loading artist details…").foregroundStyle(theme.secondary)
                            }
                        } else {
                            Text(
                                enabled
                                    ? "No biography found for this artist."
                                    : "Enable artist photos and biographies in Settings to see artist details."
                            )
                            .font(.callout).foregroundStyle(theme.secondary)
                        }
                        if enabled, let error = store.artistProfiles.error(artist) {
                            Text(error).font(.caption).foregroundStyle(theme.secondary)
                            Button("Retry") { Task { await load(force: true) } }
                        }
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        SectionTitle(title: "Albums")
                        AlbumGrid(albums: albums)
                    }
                }.padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 28)
            }.frame(maxWidth: 640).frame(maxWidth: .infinity)
                .background { NativeScrollToTop().frame(width: 0, height: 0) }
        }.ignoresSafeArea(.container, edges: .top)
            .navigationTitle("").navigationBarTitleDisplayMode(.inline).pageBackground()
            .modifier(ArtworkScrollEdges()).tint(.white)
            .toolbarBackground(.hidden, for: .navigationBar)
            .task(id: "\(artist.id):\(enabled)") { await load() }
            .sheet(isPresented: $showsAbout) {
                if let profile {
                    ArtistAboutSheet(profile: profile)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }
            }
    }
    private func load(force: Bool = false) async {
        loading = true
        defer { loading = false }
        guard enabled else { return }
        _ = await store.artistProfiles.load(artist, musicBrainzID: store.musicBrainzID(for: artist), force: force)
    }
}

private struct ArtistAboutSheet: View {
    let profile: ArtistProfile

    var body: some View {
        ScrollView {
            if let biography = profile.biography {
                Text(biography).font(.body).lineSpacing(5).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 24)
                    .readingWidth()
            }
        }
    }
}
