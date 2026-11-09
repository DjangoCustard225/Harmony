import SwiftUI
import HarmonyCore

struct DuplicateReviewView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appTheme) private var theme
    @State private var selected: Set<String> = []
    @State private var confirming = false

    private var removesWholeGroup: Bool {
        store.duplicateGroups.contains { group in group.allSatisfy { selected.contains($0.id) } }
    }

    var body: some View {
        List {
            if store.reviewingDuplicates {
                HStack {
                    ProgressView(); Text("Checking your library…")
                }
                .listRowBackground(theme.surface)
            } else if store.duplicateGroups.isEmpty {
                ContentUnavailableView("No duplicates found", systemImage: "checkmark.circle")
                    .listRowBackground(theme.surface)
            } else {
                Section {
                    Text("Select the copies you want to remove. Keep at least one copy in each group.")
                        .foregroundStyle(theme.secondary)
                }.listRowBackground(theme.surface)
                ForEach(Array(store.duplicateGroups.enumerated()), id: \.offset) { _, group in
                    Section {
                        ForEach(group) { track in
                            Button {
                                if !selected.insert(track.id).inserted { selected.remove(track.id) }
                            } label: {
                                HStack {
                                    Image(systemName: selected.contains(track.id) ? "checkmark.circle.fill" : "circle")
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(track.originalFilename ?? track.filename).foregroundStyle(.primary)
                                        Text("Added \(track.added.formatted(date: .abbreviated, time: .shortened))")
                                            .font(.caption).foregroundStyle(theme.secondary)
                                    }
                                    Spacer()
                                }
                            }
                        }
                    } header: {
                        Text("\(group[0].song.title) · \(group[0].song.artistName)")
                    }.listRowBackground(theme.surface)
                }
            }
            if !store.duplicateWarnings.isEmpty {
                Section("Couldn’t check") {
                    ForEach(Array(store.duplicateWarnings.enumerated()), id: \.offset) { _, warning in
                        Text(warning).font(.caption).foregroundStyle(theme.secondary)
                    }
                }.listRowBackground(theme.surface)
            }
        }
        .navigationTitle("Review duplicates")
        .navigationBarTitleDisplayMode(.inline)
        .pageBackground()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Remove", role: .destructive) { confirming = true }
                    .disabled(selected.isEmpty || removesWholeGroup || store.libraryBusy)
            }
        }
        .alert("Remove selected copies?", isPresented: $confirming) {
            Button("Remove", role: .destructive) {
                let ids = selected
                selected.removeAll()
                Task { await store.removeDuplicates(ids) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove \(selected.count) selected copies from Harmony?")
        }
        .task { await store.scanDuplicates() }
    }
}
