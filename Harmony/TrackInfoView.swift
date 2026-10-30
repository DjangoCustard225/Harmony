import SwiftUI
import HarmonyCore

struct TrackInfoView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appTheme) private var theme
    let song: Song
    private var track: LocalTrack? { store.library?.index.tracks.first { $0.id == song.id } }
    var body: some View {
        List {
            if let track {
                Section("Track") {
                    field("Title", track.song.title)
                    field("Artist", track.song.artist)
                    field("Album artist", track.song.albumArtist)
                    field("Album", track.song.album)
                    field("Track", track.song.track.map(String.init))
                    field("Disc", track.song.discNumber.map(String.init))
                    field("Filename", track.originalFilename ?? track.filename)
                }.listRowBackground(theme.surface)
                if let metadata = track.metadata {
                    Section("Audio") {
                        field("Format", track.song.suffix?.uppercased())
                        field("Duration", metadata.duration.map(TimeLabel.clock))
                        field("Sample rate", metadata.sampleRate.map { "\($0) Hz" })
                        field("Channels", metadata.channels.map(String.init))
                        field("Bit depth", metadata.bitsPerSample.map { "\($0) bit" })
                        field(
                            "File size",
                            metadata.fileSize.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) })
                    }.listRowBackground(theme.surface)
                }
            } else {
                ContentUnavailableView("Track no longer available", systemImage: "music.note")
            }
        }.navigationTitle("Track Info").navigationBarTitleDisplayMode(.inline).pageBackground()
    }
    @ViewBuilder private func field(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            LabeledContent(label) { Text(value).textSelection(.enabled).multilineTextAlignment(.trailing) }
        }
    }
}
