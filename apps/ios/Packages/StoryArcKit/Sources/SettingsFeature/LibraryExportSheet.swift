internal import SwiftUI
internal import UniformTypeIdentifiers

internal import DesignSystem
internal import Persistence
internal import StoryArcCore

/// The sheet where a library export is set up and handed to the system document picker.
///
/// `library-portability` tasks 2.4, 2.5 and 5.3. It says what the file holds and what it does
/// not, offers the passwords switch off, and asks for the passphrase twice only when the switch
/// is on. Android's `LibraryExportSheet` says the same, in the same order.
struct LibraryExportSheet: View {
    @Bindable var model: LibraryExportModel
    let transfer: LibraryTransfer
    let onClose: () -> Void

    @Environment(\.theme) private var theme
    @State private var isPicking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("transfer.export.carries", bundle: .module)
                    Text("transfer.export.notWhat", bundle: .module)
                    Text("transfer.export.readable", bundle: .module)
                        .foregroundStyle(theme.palette.textSecondary)
                }

                Section {
                    Toggle(isOn: $model.includesPasswords) {
                        Text("transfer.export.passwords", bundle: .module)
                    }
                    if model.includesPasswords {
                        passphraseFields
                    }
                } footer: {
                    Text("transfer.export.passwords.warning", bundle: .module)
                }

                if model.phase == .failed {
                    Section {
                        Text("transfer.export.failed", bundle: .module)
                            .foregroundStyle(theme.palette.textSecondary)
                    }
                }
            }
            .navigationTitle(Text("transfer.export.title", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { close() } label: { Text("transfer.cancel", bundle: .module) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model.phase == .working {
                        ProgressView()
                    } else {
                        Button { Task { await prepare() } } label: {
                            Text("transfer.export.action", bundle: .module)
                        }
                        .disabled(!model.canExport)
                    }
                }
            }
            .fileExporter(
                isPresented: $isPicking,
                document: model.file,
                contentType: .json,
                defaultFilename: LibraryFileDocument.defaultName(on: Date()),
                onCompletion: finished
            )
            .interactiveDismissDisabled(model.phase == .working)
        }
    }

    @ViewBuilder private var passphraseFields: some View {
        SecureField(text: $model.passphrase) {
            Text("transfer.passphrase", bundle: .module)
        }
        .noAutofill()
        SecureField(text: $model.confirmation) {
            Text("transfer.passphrase.again", bundle: .module)
        }
        .noAutofill()
        switch model.problem {
        case .empty:
            Text("transfer.export.problem.empty", bundle: .module)
                .textRole(.footnote)
                .foregroundStyle(theme.palette.textSecondary)
        case .mismatch:
            Text("transfer.export.problem.mismatch", bundle: .module)
                .textRole(.footnote)
                .foregroundStyle(theme.palette.textSecondary)
        case nil:
            EmptyView()
        }
        Text("transfer.export.passphrase.note", bundle: .module)
            .textRole(.footnote)
            .foregroundStyle(theme.palette.textSecondary)
    }

    private func prepare() async {
        await model.prepare(with: transfer, appVersion: BuildInfo.version)
        isPicking = model.file != nil
    }

    private func finished(_ result: Result<URL, any Error>) {
        guard model.pickerFinished(result) else { return }
        AccessibilityNotification.Announcement(
            String(localized: "transfer.export.done", bundle: .module, locale: .storyArc)
        ).post()
        close()
    }

    private func close() {
        model.clearSecrets()
        onClose()
    }
}

extension View {
    /// A passphrase field that is not a login: no password-manager prompt, no strong-password
    /// suggestion, no correction. The reader invents this phrase for one file.
    @ViewBuilder
    func noAutofill() -> some View {
        #if os(iOS)
        self.textContentType(nil)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        self.autocorrectionDisabled()
        #endif
    }
}
