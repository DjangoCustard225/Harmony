import SwiftUI
import UniformTypeIdentifiers
import UIKit

enum MusicImportMode: String, Identifiable {
    /// `link` opens a folder in place, so its songs play from where they are.
    case files, folder, link
    var id: Self { self }
}

/// Import copies so playback does not depend on access to the provider's original URL.
struct MusicFilePicker: UIViewControllerRepresentable {
    let mode: MusicImportMode
    let onSelection: ([URL]) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Some providers expose audio (especially FLAC) as generic data. Let users select
        // those files and validate the actual audio with AVFoundation during import.
        let picker: UIDocumentPickerViewController
        switch mode {
        case .folder:
            // Copy the selected folder into the app's temporary area so providers that
            // cannot grant recursive open-in-place access can still be imported.
            picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: true)
        case .link:
            // Opened in place (not as a copy) for lasting, recursive access to the folder.
            picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        case .files:
            // Some providers expose audio (especially FLAC) as generic data. Let users select
            // those files and validate the actual audio with AVFoundation during import.
            picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: true)
        }
        picker.allowsMultipleSelection = mode == .files
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: MusicFilePicker
        init(parent: MusicFilePicker) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.onSelection(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onCancel()
        }
    }
}

extension View {
    /// Presents the import picker for `AppStore.importMode`.
    func musicImporter() -> some View {
        modifier(MusicImporter())
    }
}

private struct MusicImporter: ViewModifier {
    @Environment(AppStore.self) private var store

    func body(content: Content) -> some View {
        @Bindable var store = store
        content.sheet(item: $store.importMode) { mode in
            MusicFilePicker(mode: mode) { urls in
                store.importMode = nil
                Task {
                    switch mode {
                    case .files: await store.importFiles(urls)
                    case .folder: if let url = urls.first { await store.importFolder(url) }
                    case .link: if let url = urls.first { await store.linkFolder(url) }
                    }
                }
            } onCancel: {
                store.importMode = nil
                store.reconnectingFolderID = nil
            }
        }
    }
}
