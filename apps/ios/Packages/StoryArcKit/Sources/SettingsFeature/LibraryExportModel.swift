internal import SwiftUI

internal import Persistence
internal import StoryArcCore

/// What the export sheet holds while the reader decides.
///
/// `library-portability` / *Secrets travel only sealed, and only when asked*: the switch starts
/// off, and the passphrase pair is checked by the one rule both platforms share. The passphrase
/// is read to seal and kept in memory only while the sheet is open; ``clearSecrets()`` lets it
/// go. It is written nowhere. Android's `LibraryExportState` is the same state.
@MainActor
@Observable
final class LibraryExportModel {
    enum Phase: Equatable {
        case editing
        case working
        case failed
    }

    /// Off by default: a reader who does nothing writes no secret.
    var includesPasswords = false
    var passphrase = ""
    var confirmation = ""

    private(set) var phase: Phase = .editing

    /// The prepared file, once there is one. Setting it is what offers the picker.
    var file: LibraryFileDocument?

    /// What is wrong with the pair, or nil. Always nil while the switch is off.
    var problem: ExportPassphraseProblem? {
        includesPasswords ? ExportPassphrase.problem(passphrase, confirmation: confirmation) : nil
    }

    var canExport: Bool { phase != .working && problem == nil }

    /// Reads the library, seals what was asked for, and holds the bytes for the picker.
    func prepare(with transfer: LibraryTransfer, appVersion: String) async {
        guard canExport else { return }
        phase = .working
        do {
            let data = try await transfer.exportData(
                appVersion: appVersion,
                passphrase: includesPasswords ? passphrase : nil
            )
            file = LibraryFileDocument(data: data)
            phase = .editing
        } catch {
            phase = .failed
        }
    }

    /// The picker closed, with a file written or without. The bytes are let go either way.
    func pickerClosed() {
        file = nil
    }

    /// The passphrase leaves memory when the sheet does.
    func clearSecrets() {
        passphrase = ""
        confirmation = ""
        file = nil
    }
}
