import SwiftUI
import HarmonyCore

struct DuplicateReviewView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appTheme) private var theme
    @State private var selected: Set<String> = []
    @State private var confirming = false
    @State private var removeAll = false
    @State private var scanned = false
    @State private var showingWarnings = false

    private var extraCopies: [LocalTrack] { store.duplicateGroups.flatMap { $0.dropFirst() } }
    private var selectedTracks: [LocalTrack] {
        Dictionary((store.duplicateGroups + store.similarGroups).flatMap { $0 }.map { ($0.id, $0) }) { a, _ in a }
            .values.filter { selected.contains($0.id) }
    }
    private func size(_ tracks: [LocalTrack]) -> String {
        ByteCountFormatter.string(
            fromByteCount: tracks.reduce(0) { $0 + ($1.fingerprint?.size ?? 0) }, countStyle: .file)
    }
    private func scan() async {
        selected.removeAll()
        // If an import or refresh is running, the scan starts when it finishes (see onChange below).
        if await store.scanDuplicates() { scanned = true }
    }
    private var warningsTitle: String {
        let count = store.duplicateWarnings.count
        return "\(count) \(count == 1 ? "file" : "files") couldn’t be checked"
    }

    var body: some View {
        Group {
            if store.duplicateGroups.isEmpty && store.similarGroups.isEmpty {
                emptyState
            } else {
                groupList
            }
        }
        .navigationTitle("Duplicates")
        .navigationBarTitleDisplayMode(.inline)
        .pageBackground()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Scan again", systemImage: "arrow.clockwise") { Task { await scan() } }
                    .disabled(store.libraryBusy || store.songs.isEmpty)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !selected.isEmpty && !store.libraryBusy {
                Button(role: .destructive) {
                    removeAll = false; confirming = true
                } label: {
                    Text(
                        "Remove \(selected.count) \(selected.count == 1 ? "copy" : "copies") · \(size(selectedTracks))"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent).tint(.red).controlSize(.large).padding()
            }
        }
        .alert(removeAll ? "Remove all duplicates?" : "Remove selected copies?", isPresented: $confirming) {
            Button("Remove", role: .destructive) {
                let ids: Set<String>? = removeAll ? nil : selected
                selected.removeAll()
                Task { await store.removeDuplicates(ids) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                removeAll
                    ? "Keep the oldest copy of each identical file and remove the extras."
                    : "Copies in Harmony are deleted. Copies in linked folders are only hidden from your library.")
        }
        .sheet(isPresented: $showingWarnings) { warningsSheet }
        .task { await scan() }
        .onChange(of: store.libraryBusy) { _, busy in
            if !busy && !scanned { Task { await scan() } }
        }
        .onChange(of: (store.duplicateGroups + store.similarGroups).flatMap { $0.map(\.id) }) { _, ids in
            selected.formIntersection(Set(ids))
        }
    }

    // MARK: Empty, loading and failure states

    @ViewBuilder private var emptyState: some View {
        if store.reviewingDuplicates || !scanned {
            ContentUnavailableView {
                VStack(spacing: 16) {
                    ProgressView().controlSize(.large)
                    Text(store.removingDuplicates ? "Removing duplicates" : "Checking for duplicates")
                        .font(.title3.weight(.semibold))
                }
            } description: {
                Text(store.duplicateProgress.isEmpty ? "Preparing…" : store.duplicateProgress)
                    .monospacedDigit().contentTransition(.numericText())
            }
        } else if store.duplicateScanFailed {
            ContentUnavailableView {
                Label("Couldn’t check duplicates", systemImage: "exclamationmark.triangle")
            } description: {
                Text(store.duplicateWarnings.first ?? "Something went wrong while reading your library.")
            } actions: {
                Button("Try again", systemImage: "arrow.clockwise") { Task { await scan() } }
                    .buttonStyle(.glass).controlSize(.large).disabled(store.libraryBusy)
            }
        } else if store.songs.isEmpty {
            LibraryEmptyState(
                title: "No songs to check", symbol: "square.on.square",
                message: "Import music and Harmony will look for identical copies.")
        } else {
            ContentUnavailableView {
                Label(
                    store.duplicateResult == nil ? "No duplicates" : "All clean",
                    systemImage: "checkmark.circle")
            } description: {
                Text(cleanDescription)
            } actions: {
                if !store.duplicateWarnings.isEmpty {
                    Button(warningsTitle, systemImage: "exclamationmark.circle") { showingWarnings = true }
                        .buttonStyle(.glass)
                }
            }
        }
    }

    private var cleanDescription: String {
        let unique =
            store.duplicateWarnings.isEmpty
            ? "No song in your library has a second copy." : "No song Harmony could read has a second copy."
        guard let result = store.duplicateResult else { return unique }
        return result + ".\n" + unique
    }

    private var warningsSheet: some View {
        NavigationStack {
            List {
                ForEach(Array(store.duplicateWarnings.enumerated()), id: \.offset) { _, warning in
                    Text(warning).font(.subheadline).foregroundStyle(theme.secondary)
                }.listRowBackground(theme.surface)
            }
            .navigationTitle(warningsTitle).navigationBarTitleDisplayMode(.inline)
            .pageBackground()
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Duplicate groups

    private var groupList: some View {
        List {
            if store.reviewingDuplicates {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(store.duplicateProgress.isEmpty ? "Checking…" : store.duplicateProgress)
                            .foregroundStyle(theme.secondary).monospacedDigit()
                    }
                }.listRowBackground(theme.surface)
            } else if let result = store.duplicateResult {
                Section {
                    Label(result, systemImage: "checkmark.circle").font(.subheadline)
                }.listRowBackground(theme.surface)
            }
            if !store.duplicateGroups.isEmpty {
                Section {
                    ForEach(store.duplicateGroups, id: \.first!.id) { group in groupRows(group) }
                    Button(
                        "Remove \(extraCopies.count) extra \(extraCopies.count == 1 ? "copy" : "copies") · \(size(extraCopies))",
                        role: .destructive
                    ) {
                        removeAll = true; confirming = true
                    }.disabled(store.libraryBusy)
                } header: {
                    Text("Identical files")
                } footer: {
                    Text("Removing all keeps the oldest copy of each song.")
                }.listRowBackground(theme.surface)
            }
            if !store.similarGroups.isEmpty {
                Section {
                    ForEach(store.similarGroups, id: \.first!.id) { group in groupRows(group) }
                } header: {
                    Text("Possible duplicates")
                } footer: {
                    Text("Same title, artist and length in different files. Tap the copies you want to remove.")
                }.listRowBackground(theme.surface)
            }
            if !store.duplicateWarnings.isEmpty {
                Section {
                    Button(warningsTitle, systemImage: "exclamationmark.circle") { showingWarnings = true }
                        .foregroundStyle(theme.secondary)
                }.listRowBackground(theme.surface)
            }
        }
    }

    @ViewBuilder private func groupRows(_ group: [LocalTrack]) -> some View {
        HStack(spacing: 12) {
            ArtworkView(id: group[0].song.coverArt, size: 100).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(group[0].song.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(group[0].song.artistName).font(.caption).foregroundStyle(theme.secondary).lineLimit(1)
            }
        }.accessibilityElement(children: .combine)
        ForEach(group) { track in copyRow(track, in: group) }
    }

    private func copyRow(_ track: LocalTrack, in group: [LocalTrack]) -> some View {
        let isSelected = selected.contains(track.id)
        // The last unselected copy in a group can't be selected, so a song is never removed entirely.
        let keep = !isSelected && group.filter { !selected.contains($0.id) }.count == 1
        let location = store.library?.location(of: track) ?? track.filename
        return Button {
            if isSelected { selected.remove(track.id) } else if !keep { selected.insert(track.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(isSelected ? Color.red : theme.secondary)
                    .opacity(keep ? 0.4 : 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(location).font(.subheadline).lineLimit(2).truncationMode(.middle)
                    Text(details(track)).font(.caption).foregroundStyle(theme.secondary)
                }
            }.padding(.leading, 56).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(store.libraryBusy || keep)
        .accessibilityLabel("\(location), \(details(track))")
        .accessibilityValue(isSelected ? "Will be removed" : keep ? "Kept" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func details(_ track: LocalTrack) -> String {
        var parts = [track.added.formatted(date: .abbreviated, time: .omitted)]
        if let bytes = track.fingerprint?.size {
            parts.append(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
        }
        return parts.joined(separator: " · ")
    }
}
