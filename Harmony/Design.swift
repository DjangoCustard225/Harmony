import SwiftUI
import HarmonyCore

enum Theme {
    static let background = Color(red: 0.035, green: 0.045, blue: 0.05)
    static let surface = Color(red: 0.075, green: 0.09, blue: 0.10)
    static let elevated = Color(red: 0.115, green: 0.13, blue: 0.14)
    static let defaultAccent = Color.white
    static let secondary = Color(red: 0.59, green: 0.65, blue: 0.63)
    static let border = Color.white.opacity(0.08)
    static let artworkCornerRadius: CGFloat = 3
    static let playerArtworkCornerRadius: CGFloat = 8
}

extension View {
    func pageBackground() -> some View {
        modifier(PageBackground())
    }

    func panel(radius: CGFloat = 22) -> some View {
        modifier(PanelBackground(radius: radius))
    }

    func readingWidth() -> some View { frame(maxWidth: 1000).frame(maxWidth: .infinity) }
}

private struct PageBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.background(AppBackground()).scrollContentBackground(.hidden).scrollEdgeEffectStyle(.soft, for: .all)
            .toolbarMinimizationBehavior(.onScrollDown, for: .navigationBar)
    }
}

private struct PanelBackground: ViewModifier {
    @Environment(\.appTheme) private var theme
    let radius: CGFloat
    func body(content: Content) -> some View {
        content.background(theme.surface, in: RoundedRectangle(cornerRadius: radius))
            .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(theme.border, lineWidth: 1) }
    }
}

struct BrandMark: View {
    @Environment(\.appTheme) private var theme
    var size: CGFloat = 64
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28).fill(theme.accent.gradient)
            Image("HarmonyMark").renderingMode(.template).resizable().scaledToFit()
                .foregroundStyle(theme.background)
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct ArtworkView: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppStore.self) private var store
    let id: String?
    var size: Int = 600
    var cornerRadius: CGFloat = Theme.artworkCornerRadius
    @State private var image: UIImage?
    var body: some View {
        // A cached cover shows in the row's first frame, so scrolling back doesn't flash the placeholder.
        let shown = id.flatMap { store.artwork.cachedImage(id: $0, size: size) } ?? image
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let shown { Image(uiImage: shown).resizable().scaledToFill() } else { ArtworkPlaceholder() }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(
                    theme.border, lineWidth: 1)
            }
            .task(id: "\(store.sessionID.uuidString):\(id ?? ""):\(size)") {
                guard let id, let library = store.library else {
                    image = nil
                    return
                }
                image = store.artwork.cachedImage(id: id, size: size)
                if image != nil { return }
                let result = await store.artwork.image(id: id, library: library, size: size)
                guard !Task.isCancelled else { return }
                image = result
            }
            .accessibilityHidden(true)
    }
}

/// Drawn in one pass (no view tree per cover), since many show at once while covers load.
private struct ArtworkPlaceholder: View {
    @Environment(\.appTheme) private var theme
    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            func circle(_ diameter: CGFloat) -> Path {
                Path(
                    ellipseIn: CGRect(
                        x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter))
            }
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .linearGradient(
                    Gradient(colors: [theme.elevated, theme.surface]), startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: size.height)))
            context.stroke(circle(side * 0.72), with: .color(.white.opacity(0.06)), lineWidth: side * 0.10)
            context.stroke(circle(side * 0.54), with: .color(.white.opacity(0.10)), lineWidth: 1)
            context.fill(circle(side * 0.30), with: .color(.black.opacity(0.35)))
            let note = context.resolve(
                Text(Image(systemName: "music.note")).font(.system(size: max(1, side * 0.14), weight: .medium))
                    .foregroundStyle(.white.opacity(0.65)))
            context.draw(note, at: center, anchor: .center)
        }
    }
}

struct AlbumCard: View {
    @Environment(\.appTheme) private var theme
    let album: Album
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ArtworkView(id: album.coverArt)
            Text(album.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
            Text(album.artistName).font(.caption).foregroundStyle(theme.secondary).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .combine)
    }
}

struct AlbumGrid: View {
    let albums: [Album]
    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 160, maximum: 280), spacing: 12, alignment: .top)],
            alignment: .leading, spacing: 16
        ) {
            ForEach(albums) { album in
                NavigationLink {
                    AlbumDetailView(album: album)
                } label: {
                    AlbumCard(album: album)
                }
                .buttonStyle(.plain)
                .contextMenu { AlbumActions(album: album) }
            }
        }
    }
}

struct AlbumActions: View {
    @Environment(AppStore.self) private var store
    let album: Album
    var body: some View {
        Button("Play", systemImage: "play.fill") { play(shuffle: false) }
        Button("Shuffle", systemImage: "shuffle") { play(shuffle: true) }
    }

    private func play(shuffle: Bool) {
        Task { await store.playAlbum(album, shuffle: shuffle) }
    }
}

/// Marks the song that's playing. The bars animate while audio plays and rest while paused.
struct PlayingIndicator: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var interface: PlaybackInterfaceState
    var body: some View {
        Image(systemName: "waveform")
            .symbolEffect(
                .variableColor.iterative.dimInactiveLayers.nonReversing,
                isActive: interface.isPlaying && !reduceMotion
            )
            .foregroundStyle(theme.accent)
            .accessibilityLabel(interface.isPlaying ? "Now playing" : "Paused")
    }
}

struct SongRow: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppStore.self) private var store
    @EnvironmentObject private var interface: PlaybackInterfaceState
    private var player: PlayerStore { store.player }
    let song: Song
    var action: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Button(action: action) {
                HStack(spacing: 10) {
                    ArtworkView(id: song.coverArt, size: 192).frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(song.title).font(.subheadline.weight(.medium)).foregroundStyle(
                            interface.current?.id == song.id ? theme.accent : .white
                        ).lineLimit(2)
                        Text(song.artistName).font(.caption).foregroundStyle(theme.secondary).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if interface.current?.id == song.id {
                        // The accent is white like every title, so mark the playing song with a symbol.
                        PlayingIndicator().font(.caption)
                    }
                    Text(TimeLabel.clock(Double(song.duration ?? 0))).font(.caption).monospacedDigit().foregroundStyle(
                        theme.secondary)
                }.frame(minHeight: 44).contentShape(Rectangle()).padding(.vertical, 4)
            }.buttonStyle(.plain)
            Menu {
                Button("Play next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                    player.add(song, next: true)
                }
                Button("Add to queue", systemImage: "text.badge.plus") { player.add(song, next: false) }
                AddToPlaylistMenu(songs: [song])
                SongFileActions(song: song)
            } label: {
                Image(systemName: "ellipsis").font(.body).foregroundStyle(theme.secondary).frame(width: 36, height: 44)
                    .contentShape(Rectangle())
            }.accessibilityLabel("Actions for \(song.title)")
        }
    }
}

/// "Add to Playlist" submenu: existing playlists, newest first, plus a new one.
struct AddToPlaylistMenu: View {
    @Environment(AppStore.self) private var store
    let songs: [Song]
    var body: some View {
        Menu {
            Button("New Playlist…", systemImage: "plus") { store.newPlaylistRequest = songs }
            if !store.playlists.isEmpty {
                Section {
                    ForEach(store.playlists.reversed()) { playlist in
                        Button(playlist.name, systemImage: "music.note.list") {
                            store.addToPlaylist(songs, playlist)
                        }
                    }
                }
            }
        } label: {
            Label("Add to Playlist", systemImage: "music.note.list")
        }
        .disabled(songs.isEmpty)
    }
}

/// Centered empty page with a direct way to import music.
struct LibraryEmptyState: View {
    @Environment(AppStore.self) private var store
    let title: String
    let symbol: String
    let message: String
    var body: some View {
        if store.library == nil {
            ContentUnavailableView(
                "Library unavailable", systemImage: "exclamationmark.triangle",
                description: Text("Harmony couldn’t open your music. Restart the app to try again."))
        } else {
            ContentUnavailableView {
                Label(title, systemImage: symbol)
            } description: {
                Text(message)
            } actions: {
                ImportMusicButton()
            }
        }
    }
}

struct ImportMusicButton: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        Button {
            store.importMode = .files
        } label: {
            if store.importing {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Importing…")
                }
            } else {
                Label("Import music", systemImage: "plus")
            }
        }
        .buttonStyle(.glass).controlSize(.large)
        .disabled(store.libraryBusy)
    }
}

struct SectionTitle: View {
    let title: String
    var body: some View {
        Text(title).font(.title3.weight(.bold)).frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ErrorCard: View {
    @Environment(\.appTheme) private var theme
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Couldn't load your music", systemImage: "exclamationmark.triangle").font(.headline)
            Text(message).font(.subheadline).foregroundStyle(theme.secondary)
            Button("Try again", systemImage: "arrow.clockwise", action: retry).buttonStyle(.bordered)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).panel()
    }
}
