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

    /// What the downloads weigh, asked of the filesystem by the caller — the same number
    /// the Downloads group states, for the same reason: the system can reclaim a download,
    /// and a total that counts bytes nobody has makes a reader distrust the screen.
    var downloadedBytes: Int64 = 0

    /// Removes every download. `settings-and-about` asks for cache, reading history *and*
    /// downloads to be "individually clearable", and the third one used to be a sentence
    /// saying nothing downloads yet. Something does now.
    var onClearDownloads: () -> Void = {}

    /// The row a search result pointed at, if the reader arrived through one.
    var highlight: SettingsAnchor?

    @Environment(\.theme) private var theme

    private let usage = StorageUsage()

    // Measured on entry and again after a clear, rather than on every frame: walking a
    // directory tree is not a thing to do while a list scrolls.
    @State private var cacheBytes: Int64 = 0
    @State private var historyBytes: Int64 = 0
    @State private var isConfirmingHistory = false
    @State private var isConfirmingDownloads = false
    @State private var diagnostic: String?

    /// What the downloads weigh *now*. Seeded from the caller and re-read after a clear,
    /// because the caller measured before this screen opened and the row has to go to zero
    /// under the reader's finger rather than on the next visit.
    @State private var downloadBytes: Int64 = 0

    var body: some View {
        HighlightingList(highlight: highlight) {
            Section {
                Text("privacy.statement", bundle: .module)
                Text("privacy.sources", bundle: .module)
                    .foregroundStyle(theme.palette.textSecondary)
            }

            Section {
                clearable(
                    title: "privacy.cache \(formattedBytes(cacheBytes))",
                    note: "privacy.cache.note",
                    anchor: .clearCache,
                    isEmpty: cacheBytes <= 0
                ) {
                    // No confirmation: a cache is by definition rebuildable, and asking
                    // twice for something with no consequence teaches a reader to click
                    // through dialogues.
                    //
                    // Awaited because clearing now includes the web view's cookies and
                    // origin storage, which WebKit answers for asynchronously.
                    Task {
                        await usage.clearCache()
                        cacheBytes = usage.cacheBytes()
                        // The title changes under VoiceOver, which neither moves nor
                        // speaks, so the reader who tapped Clear was told nothing at all.
                        // The row's own string, so there is nothing new to translate.
                        AccessibilityNotification.Announcement(
                            String(
                                localized: "privacy.cache \(formattedBytes(cacheBytes))",
                                bundle: .module,
                                locale: .storyArc
                            )
                        ).post()
                    }
                }

                clearable(
                    title: "privacy.history \(formattedBytes(historyBytes))",
                    note: "privacy.history.note",
                    anchor: .clearHistory,
                    isEmpty: historyBytes <= 0
                ) { isConfirmingHistory = true }

                clearable(
                    title: "privacy.downloads \(formattedDownloads(downloadBytes))",
                    note: "privacy.downloads.note",
                    anchor: .clearDownloads,
                    isEmpty: downloadBytes <= 0
                ) { isConfirmingDownloads = true }
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
                    // Silent for the same reason the cache row was.
                    AccessibilityNotification.Announcement(
                        String(
                            localized: "privacy.history \(formattedBytes(historyBytes))",
                            bundle: .module,
                            locale: .storyArc
                        )
                    ).post()
                }
            } label: {
                Text("privacy.clear", bundle: .module)
            }
        } message: {
            Text("privacy.clear.history.body", bundle: .module)
        }
        // Confirmed, unlike the cache: these are files a reader chose to fetch, and some
        // of them came over a connection they pay for. The body names what survives, for
        // the same reason the reset dialogue does.
        .confirmationDialog(
            Text("privacy.clear.downloads", bundle: .module),
            isPresented: $isConfirmingDownloads,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                onClearDownloads()
                downloadBytes = 0
                AccessibilityNotification.Announcement(
                    String(
                        localized: "privacy.downloads \(formattedDownloads(0))",
                        bundle: .module,
                        locale: .storyArc
                    )
                ).post()
            } label: {
                Text("privacy.clear", bundle: .module)
            }
        } message: {
            Text("privacy.clear.downloads.body", bundle: .module)
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
            .settingsHighlight(.diagnostic, when: highlight)

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
            cacheBytes: cacheBytes,
            // Read here rather than held, the way the byte totals are: the report states what
            // is configured at the moment the reader asks for it, and only the count survives
            // into the text.
            sources: SourceStore().registry()
        )
    }

    /// Reads both sizes at once, on entry and after a clear.
    ///
    /// Walking a directory tree and opening a store are not things to do while a list
    /// scrolls, which is why this is a step rather than a computed property.
    private func measure() async {
        cacheBytes = usage.cacheBytes()
        historyBytes = (try? await ProgressStore().sizeOnDisk()) ?? 0
        downloadBytes = downloadedBytes
    }

    /// The downloads total, in the units the rest of the app shows it in.
    ///
    /// The platform formatter rather than ``formattedBytes``: this is the one figure on this
    /// screen a reader can also see elsewhere — the Downloads group and the Settings summary
    /// show the same `bytesOnDisk` this way, and one number rendered two ways reads as two
    /// numbers. `spellsOutZero` is off because an empty device should read "0 kB" beside
    /// "129 kB", not "Zero kB".
    private func formattedDownloads(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file, spellsOutZero: false))
    }

    private func clearable(
        title: LocalizedStringKey,
        note: LocalizedStringKey,
        /// What search points at, so "cache" lands on the cache row rather than on the
        /// screen that happens to contain three rows that all say Clear.
        ///
        /// Doubles as what VoiceOver calls the button: an anchor's own label already *is*
        /// "Clear cache", so passing it separately stated the same fact twice and left
        /// room for the two to disagree. Three visible "Clear"s cannot be told apart by
        /// ear, and the visible label stays short because the row's title is beside it —
        /// which is exactly what a screen reader does not get.
        anchor: SettingsAnchor,
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
                .accessibilityLabel(Text(anchor.titleKey, bundle: .module))
        }
        .settingsHighlight(anchor, when: highlight)
    }
}
