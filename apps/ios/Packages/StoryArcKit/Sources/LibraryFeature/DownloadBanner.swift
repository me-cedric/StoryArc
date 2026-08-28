public import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// What the queue is doing, along the foot of the catalogue.
///
/// One line for the download at the front and a count for the rest, because a reader
/// browsing a catalogue wants to keep browsing — a list of six transfers belongs in
/// Settings, not over the grid they are reading.
///
/// `offline-downloads` wants "progress ... visible on the publication and in a single
/// downloads view". This is the first half; Settings › Downloads and storage is the second.
struct DownloadBanner: View {
    @Environment(\.theme) private var theme

    let download: Download
    /// How many more are behind this one.
    let others: Int
    let onCancel: () -> Void
    let onResume: () -> Void

    var body: some View {
        HStack(spacing: StoryArcSpace.md) {
            VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                Text(title)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textPrimary)
                    .lineLimit(1)

                if others > 0 {
                    Text("downloads.queued \(others)", bundle: .module)
                        .textRole(.caption)
                        .foregroundStyle(theme.palette.textSecondary)
                }
            }

            Spacer(minLength: 0)

            action
        }
        .padding(.horizontal, StoryArcSpace.gutter)
        .padding(.vertical, StoryArcSpace.sm)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private var title: String {
        switch download.state {
        case let .failed(reason, _):
            reason
        case .paused:
            String(
                format: String(localized: "downloads.pausedTitle", bundle: .module),
                download.title
            )
        case .queued, .running, .finished:
            String(
                format: String(localized: "catalogue.acquire.fetching", bundle: .module),
                download.title
            )
        }
    }

    /// One button, and which one depends on what would help.
    ///
    /// A failed or paused download offers a retry; one that is moving offers a stop. Two
    /// buttons on a strip this size is a strip nobody can hit either half of.
    @ViewBuilder
    private var action: some View {
        switch download.state {
        case .failed, .paused:
            Button(action: onResume) {
                Text("downloads.retry", bundle: .module)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        case .queued, .running, .finished:
            Button(role: .destructive, action: onCancel) {
                Text("downloads.stop", bundle: .module)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}
