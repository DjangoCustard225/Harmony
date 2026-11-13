import SwiftUI
import HarmonyCore

struct TrackInfoView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appTheme) private var theme
    let song: Song
    @State private var editing = false
    private var track: LocalTrack? { store.track(song.id) }
    var body: some View {
        List {
            if let track {
                Section("Track") {
                    field("Title", track.song.title)
                    field("Artist", track.song.artist)
                    field("Album artist", track.song.albumArtist)
                    field("Album", track.song.album)
                    field("Genre", track.genre)
                    field("Year", track.year.map(String.init))
                    field("Track", track.song.track.map(String.init))
                    field("Disc", track.song.discNumber.map(String.init))
                    field("Filename", track.originalFilename ?? track.filename)
                    field("Location", store.library?.location(of: track))
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
        }
        .navigationTitle("Track Info").navigationBarTitleDisplayMode(.inline).pageBackground()
        .toolbar {
            if track != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { editing = true }.disabled(store.libraryBusy)
                }
            }
        }
        .sheet(isPresented: $editing) {
            if let track { TrackEditView(track: track) }
        }
    }
    @ViewBuilder private func field(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            LabeledContent(label) { Text(value).textSelection(.enabled).multilineTextAlignment(.trailing) }
        }
    }
}

/// Edits a track's tags inside Harmony. The audio file keeps its own tags.
private struct TrackEditView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    let track: LocalTrack
    @State private var fields: TrackFields
    @State private var trackNumber = ""
    @State private var disc = ""
    @State private var year = ""

    init(track: LocalTrack) {
        self.track = track
        let fields = track.fields
        _fields = State(initialValue: fields)
        _trackNumber = State(initialValue: fields.track.map(String.init) ?? "")
        _disc = State(initialValue: fields.disc.map(String.init) ?? "")
        _year = State(initialValue: fields.year.map(String.init) ?? "")
    }

    private var edited: TrackFields {
        var value = fields
        value.track = Int(trackNumber.trimmingCharacters(in: .whitespaces))
        value.disc = Int(disc.trimmingCharacters(in: .whitespaces))
        value.year = Int(year.trimmingCharacters(in: .whitespaces))
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    text("Title", $fields.title, placeholder: track.tagFields.title)
                    text("Artist", $fields.artist)
                    text("Album artist", $fields.albumArtist)
                    text("Album", $fields.album)
                    text("Genre", $fields.genre)
                }.listRowBackground(theme.surface)
                Section {
                    number("Year", $year)
                    number("Track", $trackNumber)
                    number("Disc", $disc)
                } footer: {
                    Text(
                        "Changes are saved in Harmony. The audio file isn’t modified, and Refresh metadata keeps them.")
                }.listRowBackground(theme.surface)
                if track.edits != nil || edited != track.tagFields {
                    Section {
                        Button("Restore File Tags", systemImage: "arrow.uturn.backward", role: .destructive) {
                            let tags = track.tagFields
                            fields = tags
                            trackNumber = tags.track.map(String.init) ?? ""
                            disc = tags.disc.map(String.init) ?? ""
                            year = tags.year.map(String.init) ?? ""
                        }
                    }.listRowBackground(theme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Edit Track").navigationBarTitleDisplayMode(.inline)
            .pageBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if store.editTrack(track.id, fields: edited) { dismiss() }
                    }
                    .disabled(edited == track.fields)
                }
            }
        }
    }

    private func text(_ label: String, _ value: Binding<String>, placeholder: String = "") -> some View {
        LabeledContent(label) {
            TextField(label, text: value, prompt: Text(placeholder.isEmpty ? "None" : placeholder))
                .multilineTextAlignment(.trailing)
        }
    }

    private func number(_ label: String, _ value: Binding<String>) -> some View {
        LabeledContent(label) {
            TextField(label, text: value, prompt: Text("None")).keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .onChange(of: value.wrappedValue) { _, new in
                    let digits = String(new.filter(\.isNumber).prefix(label == "Year" ? 4 : 3))
                    if digits != new { value.wrappedValue = digits }
                }
        }
    }
}
