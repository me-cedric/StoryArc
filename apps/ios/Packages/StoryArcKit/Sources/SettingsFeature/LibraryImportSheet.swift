internal import SwiftUI

internal import DesignSystem
internal import Persistence
internal import StoryArcCore

/// The sheet that states what importing a library file will do, and then does it.
///
/// `library-portability` tasks 3.1, 5.4 and 6.8. Nothing changes until the reader taps Import.
/// A document the app refuses is refused here by name, and a wrong passphrase is stated and may
/// be tried again. Android's `LibraryImportSheet` is the same flow.
struct LibraryImportSheet: View {
    @Bindable var model: LibraryImportModel
    let transfer: LibraryTransfer
    let onImported: (LibraryImportOutcome) -> Void
    let onClose: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text("transfer.import.title", bundle: .module))
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { toolbar }
                .interactiveDismissDisabled(model.isBusy)
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle, .reading, .importing:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .preview(preview): previewForm(preview)
        case let .refused(refusal): refusedForm(refusal)
        case let .done(outcome): doneForm(outcome)
        case .failed:
            Form { Section { Text("transfer.import.failed", bundle: .module) } }
        }
    }

    // MARK: Preview

    private func previewForm(_ preview: LibraryImportPreview) -> some View {
        Form {
            Section { Text("transfer.import.intro", bundle: .module) }
            ImportPreviewList(lines: preview.plan.previewLines)
            if preview.needsPassphrase { secretsSection }
        }
    }

    private var secretsSection: some View {
        Section {
            SecureField(text: $model.passphrase) {
                Text("transfer.passphrase", bundle: .module)
            }
            .noAutofill()
            if model.passphraseRefused {
                Text("transfer.import.wrong", bundle: .module)
                    .foregroundStyle(theme.palette.textSecondary)
            }
            Button { Task { await confirm(skippingSecrets: true) } } label: {
                Text("transfer.import.withoutSecrets", bundle: .module)
            }
        } footer: {
            Text("transfer.import.secrets", bundle: .module)
        }
    }

    // MARK: Refusal

    private func refusedForm(_ refusal: LibraryImportRefusal) -> some View {
        Form {
            Section {
                Label {
                    Text("transfer.refused.title", bundle: .module)
                } icon: {
                    Image(systemName: "exclamationmark.circle")
                }
                refusalText(refusal)
                    .foregroundStyle(theme.palette.textSecondary)
            }
        }
    }

    /// The reason, by name. A newer version names both numbers and a too-large file both sizes,
    /// so the reader knows what to change.
    @ViewBuilder
    private func refusalText(_ refusal: LibraryImportRefusal) -> some View {
        switch refusal {
        case let .document(.newerThanThisApp(found, understood)):
            Text("transfer.refused.newer \(found) \(understood)", bundle: .module)
        case let .document(.tooLarge(found, limit)):
            Text("transfer.refused.tooLarge \(Self.size(found)) \(Self.size(limit))", bundle: .module)
        case .document(.notALibraryDocument):
            Text("transfer.refused.notADocument", bundle: .module)
        case .document(.noMigrationPath), .document(.malformed):
            Text("transfer.refused.damaged", bundle: .module)
        case .unopened:
            Text("transfer.refused.unopened", bundle: .module)
        }
    }

    private static func size(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    // MARK: Done

    private func doneForm(_ outcome: LibraryImportOutcome) -> some View {
        Form {
            Section {
                Label {
                    Text("transfer.done.title", bundle: .module)
                } icon: {
                    Image(systemName: "checkmark.circle")
                }
            }
            if outcome.secretsWritten > 0 {
                Section { Text("transfer.done.secrets \(outcome.secretsWritten)", bundle: .module) }
            }
            if !outcome.sourcesNeedingSignIn.isEmpty {
                Section {
                    ForEach(outcome.sourcesNeedingSignIn, id: \.self) { Text($0) }
                } header: {
                    Text("transfer.done.signIn \(outcome.sourcesNeedingSignIn.count)", bundle: .module)
                }
            }
            if !outcome.conflicts.isEmpty { conflictsSection(outcome.conflicts) }
        }
    }

    /// D3's notice, once: one title names both positions, several give the count and a list.
    /// Each conflict names its title and offers the other position (`reading-progress`).
    @ViewBuilder
    private func conflictsSection(_ conflicts: [ProgressPull.Conflict]) -> some View {
        Section {
            if let only = conflicts.first, conflicts.count == 1 {
                let kept = ConflictWords.kept(only)
                let setAside = ConflictWords.setAside(only)
                Text("transfer.done.conflict.one \(title(of: only)) \(kept) \(setAside)", bundle: .module)
                useOther(0)
            } else {
                Text("transfer.done.conflict.many \(conflicts.count)", bundle: .module)
                DisclosureGroup {
                    ForEach(Array(conflicts.enumerated()), id: \.offset) { index, conflict in
                        ConflictRow(title: title(of: conflict), conflict: conflict)
                        useOther(index)
                    }
                } label: {
                    Text("transfer.done.conflict.show", bundle: .module)
                }
            }
        }
    }

    /// The library's title, or the file's name for a publication the library no longer lists.
    private func title(of conflict: ProgressPull.Conflict) -> String {
        let identity = conflict.resolved.identity
        return transfer.title(identity)
            ?? identity.normalizedPath.map { URL(filePath: $0).lastPathComponent }
            ?? identity.contentDigest
            ?? ""
    }

    private func useOther(_ index: Int) -> some View {
        Button {
            Task { await model.useOtherPosition(at: index, transfer: transfer, onImported: onImported) }
        } label: {
            Text("transfer.done.conflict.useOther", bundle: .module)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        switch model.phase {
        case let .preview(preview):
            ToolbarItem(placement: .cancellationAction) {
                Button { onClose() } label: { Text("transfer.cancel", bundle: .module) }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button { Task { await confirm(skippingSecrets: false) } } label: {
                    Text("transfer.import.action", bundle: .module)
                }
                .disabled(preview.needsPassphrase && model.passphrase.isEmpty)
            }
        case .refused, .failed:
            ToolbarItem(placement: .confirmationAction) {
                Button { onClose() } label: { Text("transfer.ok", bundle: .module) }
            }
        case .done:
            ToolbarItem(placement: .confirmationAction) {
                Button { onClose() } label: { Text("transfer.done.action", bundle: .module) }
            }
        case .idle, .reading, .importing:
            ToolbarItem(placement: .cancellationAction) {
                Button { onClose() } label: { Text("transfer.cancel", bundle: .module) }
                    .disabled(model.isBusy)
            }
        }
    }

    private func confirm(skippingSecrets: Bool) async {
        await model.confirm(transfer: transfer, skippingSecrets: skippingSecrets, onImported: onImported)
    }
}

/// One title both devices had moved on in: the position kept and the position set aside.
struct ConflictRow: View {
    let title: String
    let conflict: ProgressPull.Conflict

    var body: some View {
        Text(
            "transfer.done.conflict.item \(title) \(ConflictWords.kept(conflict)) \(ConflictWords.setAside(conflict))",
            bundle: .module
        )
    }
}

/// A conflict's two positions, in the unit the position already keeps.
///
/// A page's own index where the page count is known, a percentage otherwise. The same rule as
/// the Kavita conflict notice, worded in this module's own catalogue.
enum ConflictWords {
    static func kept(_ conflict: ProgressPull.Conflict) -> String {
        label(conflict.resolved.position)
    }

    static func setAside(_ conflict: ProgressPull.Conflict) -> String {
        label(conflict.discarded)
    }

    static func label(_ position: ReadingPosition) -> String {
        if case let .page(index, total) = position, total > 0 {
            let format = String(localized: "transfer.position.page",
                                bundle: .module.inChosenLanguage, locale: .storyArc)
            return String(format: format, index + 1, total)
        }
        let percent = Int((position.fraction * 100).rounded())
        let format = String(localized: "transfer.position.percent", bundle: .module.inChosenLanguage, locale: .storyArc)
        return String(format: format, percent)
    }
}
