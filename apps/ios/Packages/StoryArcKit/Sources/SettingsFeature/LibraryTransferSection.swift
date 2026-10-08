internal import SwiftUI
internal import UniformTypeIdentifiers

internal import Persistence

/// The two rows that move a library to another device: export and import.
///
/// `library-portability` tasks 2.5 and 3.1. Export opens its sheet, which ends in the system
/// document picker. Import opens the system document picker, and what it returns opens the
/// preview sheet. Android's `LibraryTransferRows` offers the same two rows.
struct LibraryTransferSection: View {
    let transfer: LibraryTransfer
    var highlight: SettingsAnchor?
    let onImported: (LibraryImportOutcome) -> Void

    @State private var exportModel = LibraryExportModel()
    @State private var importModel = LibraryImportModel()
    @State private var isExporting = false
    @State private var isPicking = false
    @State private var isImporting = false

    var body: some View {
        Section {
            Button { isExporting = true } label: {
                Label {
                    Text("transfer.export", bundle: .module)
                } icon: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            .settingsHighlight(.exportLibrary, when: highlight)
            .sheet(isPresented: $isExporting, onDismiss: { exportModel.clearSecrets() }, content: {
                LibraryExportSheet(model: exportModel, transfer: transfer) { isExporting = false }
            })

            Button { isPicking = true } label: {
                Label {
                    Text("transfer.import", bundle: .module)
                } icon: {
                    Image(systemName: "square.and.arrow.down")
                }
            }
            .settingsHighlight(.importLibrary, when: highlight)
            .fileImporter(isPresented: $isPicking, allowedContentTypes: [.json], onCompletion: picked)
            .sheet(isPresented: $isImporting, onDismiss: { importModel.reset() }, content: {
                LibraryImportSheet(
                    model: importModel,
                    transfer: transfer,
                    onImported: onImported
                ) { isImporting = false }
            })
        } footer: {
            Text("transfer.section.footer", bundle: .module)
        }
    }

    private func picked(_ result: Result<URL, any Error>) {
        switch result {
        case let .success(url):
            isImporting = true
            Task { await importModel.load(url, with: transfer) }
        case let .failure(error):
            // Closing the picker is not a failure and says nothing.
            guard (error as? CocoaError)?.code != .userCancelled else { return }
            isImporting = true
            importModel.markUnopened()
        }
    }
}
