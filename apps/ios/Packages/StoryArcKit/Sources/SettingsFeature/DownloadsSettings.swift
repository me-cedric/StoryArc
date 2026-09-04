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

    /// The reader's own policy for the queue, and how to change it.
    @Binding var settings: AppSettings

    /// The row a search result pointed at, if the reader arrived through one.
    var highlight: SettingsAnchor?

    var body: some View {
        HighlightingList(highlight: highlight) {
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
