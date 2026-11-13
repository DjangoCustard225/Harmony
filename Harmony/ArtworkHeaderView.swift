import SwiftUI
import HarmonyCore

struct ArtworkHeaderView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.displayScale) private var displayScale
    let id: String?
    var artist: Artist? = nil
    /// Cover IDs for a split cover, used instead of `id` when there are at least two.
    var mosaic: [String] = []

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let pull = max(0, proxy.frame(in: .scrollView(axis: .vertical)).minY)
            // Cover fractional-pixel gaps while the native scroll view restores its top inset.
            let overlap = 1 / max(1, displayScale)
            let side = width + pull + 2 * overlap
            let extensionHeight: CGFloat = 140
            ZStack(alignment: .top) {
                // Continue the artwork's colors beneath the title before fading into OLED black.
                artwork.frame(width: side, height: side)
                    .scaleEffect(x: 1.12, y: 1 + (extensionHeight + 64) / max(1, side), anchor: .top)
                    .blur(radius: 32)
                    .frame(width: side, height: side + extensionHeight, alignment: .top)
                    .mask {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .clear, location: 0.32),
                                .init(color: .white, location: 0.55),
                                .init(color: .white, location: 0.78),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .top, endPoint: .bottom)
                    }
                artwork.frame(width: side, height: side)
                    .mask {
                        LinearGradient(
                            stops: [
                                .init(color: .white, location: 0),
                                .init(color: .white, location: 0.5),
                                .init(color: .white.opacity(0.7), location: 0.72),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .top, endPoint: .bottom)
                    }
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: 0.48),
                        .init(color: theme.background.opacity(0.15), location: 0.65),
                        .init(color: theme.background.opacity(0.7), location: 0.85),
                        .init(color: theme.background, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: side + extensionHeight)
                LinearGradient(colors: [.black.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 140)
            }
            .frame(width: side, height: side + extensionHeight).clipped()
            .frame(width: width, height: width, alignment: .top)
            .offset(y: -pull - overlap)
        }.aspectRatio(1, contentMode: .fit)
            .transaction { $0.animation = nil }
            .accessibilityHidden(true)
    }

    @ViewBuilder private var artwork: some View {
        if let artist {
            ArtistPortraitView(artist: artist)
        } else if mosaic.count > 1 {
            ArtworkMosaic(ids: mosaic)
        } else {
            ArtworkView(id: mosaic.first ?? id, size: 1200, cornerRadius: 0)
        }
    }

}

struct ArtworkScrollEdges: ViewModifier {
    func body(content: Content) -> some View {
        content
            // Full-bleed artwork handles the top edge itself. Keep its viewport fixed as
            // navigation controls minimize, and avoid switching a second edge backdrop.
            .toolbarMinimizationSafeAreaAdjustment(.disabled, for: .navigationBar)
            .scrollEdgeEffectHidden(true, for: .top)
    }
}

/// Up to four covers split into one square: halves for two, a half and two quarters for three,
/// and a 2×2 grid for four.
struct ArtworkMosaic: View {
    let ids: [String]
    /// Pixel size requested for each quarter; a single cover asks for twice this.
    var tileSize = 600

    var body: some View {
        let ids = Array(ids.prefix(4))
        Color.clear.aspectRatio(1, contentMode: .fit).overlay {
            switch ids.count {
            case 0: ArtworkView(id: nil, cornerRadius: 0)
            case 1: tile(ids[0], size: tileSize * 2)
            case 2:
                HStack(spacing: 0) {
                    tile(ids[0]); tile(ids[1])
                }
            case 3:
                HStack(spacing: 0) {
                    tile(ids[0])
                    VStack(spacing: 0) {
                        tile(ids[1]); tile(ids[2])
                    }
                }
            default:
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        tile(ids[0]); tile(ids[1])
                    }
                    HStack(spacing: 0) {
                        tile(ids[2]); tile(ids[3])
                    }
                }
            }
        }
        .clipped()
    }

    /// Fills its slot with the cover, cropping the overflow so halves stay edge to edge.
    private func tile(_ id: String, size: Int? = nil) -> some View {
        Color.clear.overlay {
            ArtworkView(id: id, size: size ?? tileSize, cornerRadius: 0).aspectRatio(1, contentMode: .fill)
        }
        .clipped()
    }
}
