import SwiftUI
import HarmonyCore

struct DuplicateReviewView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appTheme) private var theme
    @State private var selected: Set<String> = []
    @State private var confirming = false
    @State private var removeAll = false
    @State private var scanned = false

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

    var body: some View {
        List {
            if store.reviewingDuplicates {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.removingDuplicates ? "Removing duplicates…" : "Checking your library…")
                            Text(store.duplicateProgress).font(.caption).foregroundStyle(theme.secondary)
                        }
                    }.accessibilityElement(children: .combine)
                }.listRowBackground(theme.surface)
            }
            if let result = store.duplicateResult {
                Section {
                    Label(result, systemImage: "info.circle").font(.subheadline)
                }.listRowBackground(theme.surface)
            }
            if !store.duplicateGroups.isEmpty {
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
            } else if scanned && !store.reviewingDuplicates {
                ContentUnavailableView {
                    Label(
                        store.duplicateScanFailed ? "Couldn’t check duplicates" : "No duplicates found",
                        systemImage: store.duplicateScanFailed ? "exclamationmark.triangle" : "checkmark.circle")
                } description: {
                    Text(
                        store.duplicateWarnings.isEmpty
                            ? "Your library has no identical copies."
                            : "Some files couldn’t be checked. Try scanning again.")
                } actions: {
                    Button("Scan again") { Task { await scan() } }.disabled(store.libraryBusy)
                }.listRowBackground(theme.surface)
            }
            if !store.duplicateWarnings.isEmpty {
                Section {
                    DisclosureGroup("\(store.duplicateWarnings.count) items couldn’t be checked or removed") {
                        ForEach(Array(store.duplicateWarnings.enumerated()), id: \.offset) { _, warning in
                            Text(warning).font(.caption).foregroundStyle(theme.secondary)
                        }
                    }
                }.listRowBackground(theme.surface)
            }
        }
        .listSectionSpacing(.compact)
        .navigationTitle("Duplicates")
        .navigationBarTitleDisplayMode(.inline)
        .pageBackground()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Scan again", systemImage: "arrow.clockwise") { Task { await scan() } }
                    .disabled(store.libraryBusy)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !selected.isEmpty && !store.libraryBusy {
                Button(role: .destructive) {
                    removeAll = false; confirming = true
                } label: {
                    Text("Remove \(selected.count) copies · \(size(selectedTracks))")
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
                    ? "Keep the oldest copy of each identical file and remove the extras. Playback stops if a queued copy is removed."
                    : "Keep the unselected copies and remove your selection. Playback stops if a queued copy is removed."
            )
        }
        .task { await scan() }
        .onChange(of: store.duplicateGroups.flatMap { $0.map(\.id) }) { _, ids in
            selected.formIntersection(Set(ids))
        }
    }

    private var summary: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(extraCopies.count) extra copies · \(size(extraCopies))").font(.headline)
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
