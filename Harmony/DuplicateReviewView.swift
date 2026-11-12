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
        store.duplicateGroups.flatMap { $0 }.filter { selected.contains($0.id) }
    }
    private func size(_ tracks: [LocalTrack]) -> String {
        ByteCountFormatter.string(
            fromByteCount: tracks.reduce(0) { $0 + ($1.fingerprint?.size ?? 0) }, countStyle: .file)
    }
    private func scan() async {
        selected.removeAll()
        await store.scanDuplicates()
        scanned = true
    }
    private var warningsTitle: String {
        let count = store.duplicateWarnings.count
        return "\(count) \(count == 1 ? "file" : "files") couldn’t be checked"
    }

    var body: some View {
        Group {
            if store.duplicateGroups.isEmpty {
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
                    .frame(maxWidth: .infinity).padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent).tint(.red).padding().background(.bar)
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
                    : "Keep the unselected copies and remove your selection.")
        }
        .sheet(isPresented: $showingWarnings) { warningsSheet }
        .task { await scan() }
        .onChange(of: store.duplicateGroups.flatMap { $0.map(\.id) }) { _, ids in
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
            ? "Every song in your library is a unique file." : "Every file Harmony could read is unique."
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
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.removingDuplicates ? "Removing duplicates…" : "Checking your library…")
                            Text(store.duplicateProgress).font(.caption).foregroundStyle(theme.secondary)
                                .monospacedDigit()
                        }
                    }.accessibilityElement(children: .combine)
                }.listRowBackground(theme.surface)
            }
            if let result = store.duplicateResult {
                Section {
                    Label(result, systemImage: "info.circle").font(.subheadline)
                }.listRowBackground(theme.surface)
            }
            summary
            ForEach(store.duplicateGroups, id: \.first!.id) { group in
                Section {
                    ForEach(group) { track in copyRow(track, in: group) }
                } header: {
                    HStack(spacing: 10) {
                        ArtworkView(id: group[0].song.coverArt, size: 100, cornerRadius: 6)
                            .frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group[0].song.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            Text(group[0].song.artistName).font(.caption)
                        }
                        Spacer(minLength: 4)
                        Text("\(group.count) copies").font(.caption)
                    }.textCase(nil)
                }.listRowBackground(theme.surface)
            }
            if !store.duplicateWarnings.isEmpty {
                Section {
                    DisclosureGroup(warningsTitle) {
                        ForEach(Array(store.duplicateWarnings.enumerated()), id: \.offset) { _, warning in
                            Text(warning).font(.caption).foregroundStyle(theme.secondary)
                        }
                    }
                }.listRowBackground(theme.surface)
            }
        }
        .listSectionSpacing(.compact)
    }

    private var summary: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    "\(extraCopies.count) extra \(extraCopies.count == 1 ? "copy" : "copies") · \(size(extraCopies))"
                ).font(.headline)
                Text("Identical files only. Keep at least one copy per group.")
                    .font(.subheadline).foregroundStyle(theme.secondary)
            }.padding(.vertical, 4)
            Button(selected.isEmpty ? "Select extra copies" : "Clear selection") {
                selected = selected.isEmpty ? Set(extraCopies.map(\.id)) : []
            }
            Button("Remove all duplicates", role: .destructive) {
                removeAll = true; confirming = true
            }
        }.listRowBackground(theme.surface).disabled(store.libraryBusy)
    }

    private func copyRow(_ track: LocalTrack, in group: [LocalTrack]) -> some View {
        let isSelected = selected.contains(track.id)
        let keep = !isSelected && group.filter { !selected.contains($0.id) }.count == 1
        return Button {
            if isSelected { selected.remove(track.id) } else if !keep { selected.insert(track.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : (keep ? "lock.circle" : "circle"))
                    .font(.title3).foregroundStyle(keep ? theme.secondary : theme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.originalFilename ?? track.filename).lineLimit(2).foregroundStyle(.primary)
                    Text(track.added, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                        .font(.caption).foregroundStyle(theme.secondary)
                }
                Spacer(minLength: 4)
                if keep {
                    Text("Keep").font(.caption.weight(.semibold)).foregroundStyle(theme.secondary)
                } else if track.id == group.first?.id {
                    Text("Oldest").font(.caption).foregroundStyle(theme.secondary)
                }
            }.padding(.vertical, 3).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(store.libraryBusy || keep)
        .accessibilityLabel(
            "\(track.originalFilename ?? track.filename), \(keep ? "Keeping this copy" : isSelected ? "Selected for removal" : "Not selected")"
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
