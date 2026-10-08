internal import SwiftUI

internal import Persistence
internal import StoryArcCore

/// Why the import screen shows a refusal instead of a preview.
enum LibraryImportRefusal: Equatable {
    /// The document was read and refused, by name.
    case document(LibraryDocumentFailure)

    /// The file could not be opened or read at all.
    case unopened
}

/// The import flow, from the file the reader picked to what the import did.
///
/// `library-portability` / *The reader sees what will happen first*. Reading a file plans the
/// import and changes nothing; only ``confirm(transfer:skippingSecrets:onImported:)`` does. A
/// file over the size limit is refused from the size the file system reports, before a byte of
/// it is read (task 6.5). Android's `LibraryImportState` is the same flow.
@MainActor
@Observable
final class LibraryImportModel {
    enum Phase: Equatable {
        case idle
        case reading
        case preview(LibraryImportPreview)
        case refused(LibraryImportRefusal)
        case importing
        case done(LibraryImportOutcome)
        case failed
    }

    private(set) var phase: Phase = .idle

    /// What the reader typed for the sealed passwords. Cleared when the import ends.
    var passphrase = ""

    /// The last passphrase did not open the passwords. The reader may try again.
    private(set) var passphraseRefused = false

    var isBusy: Bool { phase == .reading || phase == .importing }

    func begin() {
        phase = .reading
        passphrase = ""
        passphraseRefused = false
    }

    /// The picker returned an error instead of a file.
    func markUnopened() {
        phase = .refused(.unopened)
    }

    /// Reads the picked file and plans the import. Changes nothing on the device.
    func load(_ url: URL, with transfer: LibraryTransfer) async {
        begin()
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            try LibraryDocumentCoder.admits(byteCount: size)
            let data = try await Task.detached { try Data(contentsOf: url) }.value
            phase = .preview(try await transfer.preview(data))
        } catch let failure as LibraryDocumentFailure {
            phase = .refused(.document(failure))
        } catch {
            phase = .refused(.unopened)
        }
    }

    /// Merges the document into the library.
    ///
    /// - Parameter skippingSecrets: import everything but the passwords; those libraries ask
    ///   for a sign-in.
    func confirm(
        transfer: LibraryTransfer,
        skippingSecrets: Bool,
        onImported: (LibraryImportOutcome) -> Void
    ) async {
        guard case let .preview(preview) = phase else { return }
        phase = .importing
        do {
            let outcome = try await transfer.performImport(
                preview,
                passphrase: skippingSecrets ? nil : passphrase
            )
            passphrase = ""
            phase = .done(outcome)
            onImported(outcome)
        } catch LibraryImportFailure.passphraseRefused {
            passphraseRefused = true
            phase = .preview(preview)
        } catch {
            passphrase = ""
            phase = .failed
        }
    }

    /// The sheet closed. Nothing of the file or the passphrase stays.
    func reset() {
        passphrase = ""
        passphraseRefused = false
        phase = .idle
    }
}
