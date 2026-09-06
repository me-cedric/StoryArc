internal import SwiftUI

internal import DesignSystem
internal import Persistence
internal import StoryArcCore

/// What the reader has asked of the queue, and what it has spent.
///
/// This screen used to be the whole downloads feature: the policy, the queue, every file on
/// the device and the only way to remove one — inside a modal, behind a list of settings
/// groups. `offline-downloads` now makes *everything on this device* one of the app's three
/// destinations, so the files, the queue and removal left for the Downloads tab, which is
/// where a reader looks for them and where they are reachable in one tap.
///
/// What stays is what is genuinely a setting: whether to wait for Wi-Fi, how much disk to
/// spend, whether a finished publication keeps its download — three choices that change
/// what the queue *does* rather than what is in it — and the total, because a reader
/// standing in the storage screen is asking how much room this app takes and deserves the
/// number without being sent somewhere else for it.
struct DownloadsSettings: View {
    @Environment(\.theme) private var theme

    /// What the files actually weigh. Asked of the filesystem by the caller, because the
    /// system can reclaim a download and a total that counts bytes nobody has is the kind
    /// of number that makes a reader distrust the whole screen.
    let bytesOnDisk: Int64

    /// What is on the device and what is still on its way.
    ///
    /// Handed in for the reason `bytesOnDisk` is: the downloads belong to the library that
    /// fetched them, and a feature module never depends on another feature module. The
    /// records are also the whole of what this screen needs to say why the queue is waiting —
    /// ``DownloadLibrary/hold(limit:)`` reads them, so no queue has to be alive.
    var downloads: DownloadLibrary = DownloadLibrary()

    /// The reader's own policy for the queue, and how to change it.
    @Binding var settings: AppSettings

    /// The row a search result pointed at, if the reader arrived through one.
    var highlight: SettingsAnchor?

    var body: some View {
        HighlightingList(highlight: highlight) {
            waiting
            policy

            Section {
                LabeledContent {
                    Text(DownloadStore.formatted(bytesOnDisk))
                        .foregroundStyle(theme.palette.textSecondary)
                } label: {
                    Text("downloads.total", bundle: .module)
                        .foregroundStyle(theme.palette.textPrimary)
                }
            } footer: {
                // Said rather than implied, twice over. A reader who came here looking for
                // their files has to be told where they went, or the move is a feature that
                // vanished — and a reader looking at this figure has to be told what it
                // counts, or the nine publications on the Downloads shelf make it a lie.
                // It counts what StoryArc fetched or imported; a folder the reader added is
                // readable with no network and is nobody's bytes but theirs.
                Text("downloads.manageInDestination", bundle: .module)
            }
        }
        .navigationTitle(Text("settings.downloads", bundle: .module))
    }
}

extension DownloadsSettings {
    /// Why the queue is waiting, and what ends the wait.
    ///
    /// `offline-downloads` requires a held queue to say what it is waiting for, and until now
    /// nothing on either platform drew ``DownloadLibrary/hold(limit:)`` at all: a reader whose
    /// queue was waiting saw a list that had simply stopped.
    ///
    /// **The remedy is said, not only the state.** "Waiting for Wi-Fi" is a fact; what a
    /// reader needs from it is that nothing is asked of them, because the queue starts again
    /// by itself. The two cases where it does say so, and the one where it does not names the
    /// two things that would end it.
    ///
    /// Nothing is drawn when the queue is not held — an empty explanation of an absent problem
    /// is the noise this row exists to avoid.
    @ViewBuilder
    fileprivate var waiting: some View {
        if let hold = downloads.hold(limit: settings.maximumDownloadBytes) {
            Section {
                VStack(alignment: .leading) {
                    // The pause reason's own sentence, already translated and already drawn on
                    // the row of every held download — `DownloadQueueSection.swift`, and
                    // `DownloadsParts.kt` on Android. Said once here rather than written a
                    // second time, so the screen and the queue cannot disagree in one language.
                    Text(hold.stateKey, bundle: .module)
                        .foregroundStyle(theme.palette.textPrimary)
                    Text(hold.remedyKey, bundle: .module)
                        .textRole(.footnote)
                        .foregroundStyle(theme.palette.textTertiary)
                }
            }
        }
    }

    /// What the reader has asked of the queue.
    ///
    /// The three `offline-downloads` calls policy: whether to wait for Wi-Fi, how much disk
    /// to spend, and whether a finished publication keeps its download. All three change
    /// what the queue does rather than what is in it, which is why they are what stayed
    /// behind when the files left for their own destination.
    @ViewBuilder
    fileprivate var policy: some View {
        Section {
            Toggle(isOn: $settings.downloadOverWifiOnly) {
                VStack(alignment: .leading) {
                    Text("downloads.wifiOnly", bundle: .module)
                    Text("downloads.wifiOnly.note", bundle: .module)
                        .textRole(.footnote)
                        .foregroundStyle(theme.palette.textTertiary)
                }
            }
            .settingsHighlight(.downloadsWiFiOnly, when: highlight)

            Toggle(isOn: $settings.removeDownloadsAfterFinishing) {
                VStack(alignment: .leading) {
                    Text("downloads.removeAfter", bundle: .module)
                    Text("downloads.removeAfter.note", bundle: .module)
                        .textRole(.footnote)
                        .foregroundStyle(theme.palette.textTertiary)
                }
            }
            .settingsHighlight(.downloadsRemoveAfterFinishing, when: highlight)

            // A short ladder rather than a free number: a reader knows "about five
            // gigabytes", not 5_000_000_000, and a field for a byte count is a way to
            // mistype one. Round decimal values, because that is how a size is shown.
            Picker(selection: $settings.maximumDownloadBytes) {
                Text("downloads.limit.none", bundle: .module).tag(Int64?.none)
                ForEach(Self.limits, id: \.self) { limit in
                    Text(limit.formatted(.byteCount(style: .file))).tag(Int64?.some(limit))
                }
            } label: {
                Text("downloads.limit", bundle: .module)
            }
            .settingsHighlight(.downloadsLimit, when: highlight)
        }
    }

    fileprivate static let limits: [Int64] = [1_000_000_000, 5_000_000_000, 20_000_000_000]
}

extension DownloadHold {
    /// What the queue is waiting for.
    ///
    /// Two of the three reuse the sentence the pause reason already carries, because they are
    /// the same fact told to the same reader. The third has no pause reason: the reader's own
    /// maximum stops the queue without marking a row, so it needs a sentence of its own.
    var stateKey: LocalizedStringKey {
        switch self {
        case .outOfSpace: "downloads.paused.outOfSpace"
        case .waitingForWifi: "downloads.paused.waitingForWiFi"
        case .storageFull: "downloads.held.storageFull"
        }
    }

    /// What ends the wait.
    ///
    /// Two of them end by themselves, and saying so is the point: a reader told only that the
    /// queue is waiting is a reader looking for a button that should not exist. The third is
    /// the reader's own choice, so it names both ways out — and names them without ruling out
    /// the offer to free room that `offline-downloads` asks for and this screen does not make.
    var remedyKey: LocalizedStringKey {
        switch self {
        case .outOfSpace: "downloads.held.outOfSpace.note"
        case .waitingForWifi: "downloads.held.waitingForWifi.note"
        case .storageFull: "downloads.held.storageFull.note"
        }
    }
}
