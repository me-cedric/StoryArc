internal import SwiftUI

internal import DesignSystem
internal import Persistence
internal import StoryArcCore

/// The privacy posture, stated rather than toggled.
///
/// `settings-and-about` asks for this to be "verifiable rather than merely stated", and
/// the reason there is nothing to switch here is the point: the app has no account, no
/// backend and no analytics, so there is nothing to opt out of. A screen full of disabled
/// toggles would imply the opposite.
struct PrivacySettings: View {
    /// Read rather than bound. The diagnostic reports what is stored; it never changes it.
    let settings: AppSettings
    let readerStore: ReaderPreferences

    @Environment(\.theme) private var theme

    private let usage = StorageUsage()

    // Measured on entry and again after a clear, rather than on every frame: walking a
    // directory tree is not a thing to do while a list scrolls.
    @State private var cacheBytes: Int64 = 0
    @State private var historyBytes: Int64 = 0
    @State private var isConfirmingHistory = false
    @State private var diagnostic: String?

    var body: some View {
        List {
            Section {
                Text("privacy.statement", bundle: .module)
                Text("privacy.sources", bundle: .module)
                    .foregroundStyle(theme.palette.textSecondary)
            }

            Section {
                clearable(
                    title: "privacy.cache \(formattedBytes(cacheBytes))",
                    note: "privacy.cache.note",
                    isEmpty: cacheBytes <= 0
                ) {
                    // No confirmation: a cache is by definition rebuildable, and asking
                    // twice for something with no consequence teaches a reader to click
                    // through dialogues.
                    usage.clearCache()
                    cacheBytes = usage.cacheBytes()
                }

                clearable(
                    title: "privacy.history \(formattedBytes(historyBytes))",
                    note: "privacy.history.note",
                    isEmpty: historyBytes <= 0
                ) { isConfirmingHistory = true }
            }

            Section {
                Text("privacy.downloads.absent", bundle: .module)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textTertiary)
            }

            diagnosticSection
        }
        .task { await measure() }
        .confirmationDialog(
            Text("privacy.clear.history", bundle: .module),
            isPresented: $isConfirmingHistory,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                Task {
                    try? await ProgressStore().clear()
                    await measure()
                }
            } label: {
                Text("privacy.clear", bundle: .module)
            }
        } message: {
            Text("privacy.clear.history.body", bundle: .module)
        }
    }

    /// The diagnostic export, shown before it can be shared.
    ///
    /// Inline rather than on its own screen. `settings-and-about` requires the reader to
    /// see the text before sharing it, and a screen they have to navigate to and back
    /// from puts distance between reading it and deciding — which is the one moment that
    /// matters here.
    @ViewBuilder private var diagnosticSection: some View {
        Section {
            VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                Text("privacy.diagnostic", bundle: .module)
                Text("privacy.diagnostic.note", bundle: .module)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textTertiary)
            }

            Button {
                // Built on tap rather than on appearance. It reads three stores, and a
                // Privacy screen should not do that to draw a row nobody expanded.
                diagnostic = diagnostic == nil ? report() : nil
            } label: {
                Text(
                    diagnostic == nil ? "privacy.diagnostic.show" : "privacy.diagnostic.hide",
                    bundle: .module
                )
            }

            if let diagnostic {
                Text(diagnostic)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(theme.palette.textSecondary)
                    .textSelection(.enabled)

                // Share only. The system sheet already offers Copy, and a second button
                // beside it would be StoryArc reimplementing a platform affordance.
                ShareLink(item: diagnostic) {
                    Text("privacy.diagnostic.share", bundle: .module)
                }
            }
        }
    }

    private func report() -> String {
        Diagnostic.text(
            settings: settings,
            readerStore: readerStore,
            historyBytes: historyBytes,
            cacheBytes: cacheBytes
        )
    }

    /// Reads both sizes at once, on entry and after a clear.
    ///
    /// Walking a directory tree and opening a store are not things to do while a list
    /// scrolls, which is why this is a step rather than a computed property.
    private func measure() async {
        cacheBytes = usage.cacheBytes()
        historyBytes = (try? await ProgressStore().sizeOnDisk()) ?? 0
    }

    private func clearable(
        title: LocalizedStringKey,
        note: LocalizedStringKey,
        isEmpty: Bool,
        clear: @escaping () -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                Text(title, bundle: .module)
                Text(note, bundle: .module)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textTertiary)
            }
            Spacer()
            Button(action: clear) { Text("privacy.clear", bundle: .module) }
                .buttonStyle(.bordered)
                .disabled(isEmpty)
        }
    }
}
