import SwiftUI

import DesignSystem
import LibraryFeature
import Persistence
import StoryArcCore

/// What is arriving, pinned above the shelf it is arriving into.
///
/// `offline-downloads`, as modified by the three-destination change: transfers "appear at
/// the top of the on-device destination, listing active, queued and failed items with
/// per-item and global pause, resume, cancel and reorder — and when nothing is in flight
/// the queue is absent rather than shown empty, and the destination is just the readable
/// library". The absence is the caller's job: this view is only built when there is
/// something in it, so there is no empty state here to get wrong.
///
/// A row is deliberately not a cover. A transfer is not a book yet — it has no artwork on
/// this device to draw — and giving it a cell the same size as a finished publication is
/// how a downloads screen turns back into the queue inspector this destination exists to
/// stop being.
///
/// **Stop, reorder, retry, pause and resume — per row and across the whole queue.** Each one
/// goes to the one app-level ``LibraryFeature/DownloadQueue`` (dl-core 1.1): Stop cancels the
/// transfer, reorder moves the record, Retry resumes a failed row and starts it, and Pause and
/// Resume hold a row where it is and put it back. `offline-downloads`' second requirement asks
/// for "per-item and global pause, resume, cancel" together, which is what the three buttons
/// above the list send to every row at once.
struct DownloadQueueSection: View {
    @Environment(\.theme) private var theme

    /// Active, queued and failed, in the order they will be worked through.
    let downloads: [Download]

    /// Moves a queued download one place; `true` is later.
    let onReorder: (Download, Bool) -> Void

    /// Holds one download where it is. Called for a queued or running download and no other.
    let onPause: (Download) -> Void

    /// Puts a paused download back in the queue. Called for a paused download and no other.
    let onResume: (Download) -> Void

    /// Takes one out of the queue altogether, confirmed by the caller.
    let onStop: (Download) -> Void

    /// Puts a failed one back in the queue. Called for a failed download and no other.
    let onRetry: (Download) -> Void

    /// Holds every queued or running download where it is.
    let onPauseAll: () -> Void

    /// Puts every paused or failed download back in the queue.
    let onResumeAll: () -> Void

    /// Takes every download still pending out of the queue altogether, confirmed by the caller.
    let onStopAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.md) {
            HStack(spacing: StoryArcSpace.sm) {
                title
                Spacer(minLength: 0)
                allMenu
            }
            .padding(.horizontal, StoryArcSpace.gutter)

            VStack(spacing: StoryArcSpace.sm) {
                ForEach(downloads) { download in
                    DownloadQueueRow(
                        download: download,
                        // Only a queued download has an order to change: a running one has
                        // started, and the list is short enough that its ends are obvious.
                        canReorder: download.state == .queued,
                        onReorder: { onReorder(download, $0) },
                        onPause: { onPause(download) },
                        onResume: { onResume(download) },
                        onStop: { onStop(download) },
                        onRetry: { onRetry(download) }
                    )
                }
            }
            .padding(.horizontal, StoryArcSpace.gutter)
        }
    }

    private var title: some View {
        Text("downloads.inFlight")
            .textRole(.title3)
            .foregroundStyle(theme.palette.textPrimary)
    }

    /// Pause, resume and cancel for the whole queue, as one menu. Three small buttons side by
    /// side were each 28 pt tall, and a finger hit the wrong one.
    private var allMenu: some View {
        Menu {
            ForEach(Array(DownloadAllAction.groups.enumerated()), id: \.offset) { _, group in
                Section {
                    ForEach(group, id: \.self) { action in
                        Button(role: action.isDestructive ? .destructive : nil) { perform(action) } label: {
                            Label { Text(action.titleKey) } icon: { Image(systemName: action.symbol) }
                        }
                    }
                }
            }
        } label: {
            Label { Text("downloads.all") } icon: { Image(systemName: "ellipsis.circle") }
                .hitRegion()
        }
    }

    private func perform(_ action: DownloadAllAction) {
        switch action {
        case .pauseAll: onPauseAll()
        case .resumeAll: onResumeAll()
        case .cancelAll: onStopAll()
        }
    }
}

extension DownloadAllAction {
    fileprivate var titleKey: LocalizedStringKey {
        switch self {
        case .pauseAll: "downloads.pauseAll"
        case .resumeAll: "downloads.resumeAll"
        case .cancelAll: "downloads.cancelAll"
        }
    }

    fileprivate var symbol: String {
        switch self {
        case .pauseAll: "pause.circle"
        case .resumeAll: "play.circle"
        case .cancelAll: "xmark.circle"
        }
    }
}

/// One transfer: what it is, where it has got to, and what a reader can do to it.
///
/// **Except on a failure, the verb was wrong.** A transfer that has already stopped cannot
/// be stopped, and this row's only control was *Stop* — under a line reading "Failed after 3
/// attempts". `offline-downloads` asks a failed download for "a plain-language reason and a
/// retry action", and the reason was here without the action. So a failed row offers *Retry*
/// first and *Remove download* beside it, which is the rule ``LibraryFeature/DownloadBanner``
/// already followed one screen away, and which Android's `DownloadQueueRow` adopted a day
/// before this one.
///
/// **A paused row offers Resume rather than Pause**, whatever paused it — the reader, a
/// metered connection or low space — the same as ``LibraryFeature/DownloadBanner`` already
/// offers a retry for any of the three. Asking to resume a row still held for Wi-Fi or space
/// re-queues it and lets `pump()` pause it again on its own, which is the same honest
/// round trip a reader's own retry on a failed row makes.
private struct DownloadQueueRow: View {
    @Environment(\.theme) private var theme

    /// At the accessibility sizes the title and its three controls cannot share a line:
    /// the title truncates to two characters while *Stop* wraps to two lines, which is
    /// neither readable nor tappable. Above the threshold the row becomes two.
    @Environment(\.dynamicTypeSize) private var typeSize

    let download: Download
    let canReorder: Bool
    let onReorder: (Bool) -> Void

    /// Holds this row where it is. Shown only for a queued or running download — a row
    /// already paused or failed has nothing left to pause.
    let onPause: () -> Void

    /// Puts this row back in the queue. Shown for every paused row, whatever paused it —
    /// see the type's own note on why a hold for Wi-Fi or space offers it too.
    let onResume: () -> Void

    let onStop: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.xs) {
            HStack(spacing: StoryArcSpace.sm) {
                title.lineLimit(typeSize.isAccessibilitySize ? 3 : 2)
                Spacer(minLength: 0)
                controls
            }

            state
        }
        .padding(StoryArcSpace.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.palette.surfaceRaised, in: RoundedRectangle(cornerRadius: StoryArcRadius.md))
    }

    private var title: some View {
        Text(download.title)
            .foregroundStyle(theme.palette.textPrimary)
    }

    /// Everything a reader can do to this transfer, as one menu: *Retry* and *Remove download*
    /// on a failure, *Resume* and *Remove download* on a hold, and on a transfer that is moving
    /// *Pause*, where there is an order to change the two moves, and *Stop*.
    ///
    /// Up to four buttons side by side, each 28 pt tall and 8 pt from the next, were one too
    /// close to hit. The system draws each row of a menu at full height. What the menu holds is
    /// ``LibraryFeature/DownloadRowMenu``'s, and the removal is its last row. The caller
    /// confirms *Stop* and *Remove download*, as before.
    private var controls: some View {
        Menu {
            ForEach(Array(DownloadRowMenu.groups(for: download.state, canReorder: canReorder).enumerated()),
                    id: \.offset) { _, group in
                Section {
                    ForEach(group, id: \.self) { action in
                        Button(role: action.isDestructive ? .destructive : nil) { perform(action) } label: {
                            Label { text(of: action) } icon: { Image(systemName: action.symbol) }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle").hitRegion()
        }
        .foregroundStyle(theme.palette.textSecondary)
        .accessibilityLabel(Text("downloads.actions \(download.title)"))
    }

    private func perform(_ action: DownloadRowAction) {
        switch action {
        case .retry: onRetry()
        case .resume: onResume()
        case .pause: onPause()
        case .moveEarlier: onReorder(false)
        case .moveLater: onReorder(true)
        case .stop, .remove: onStop()
        }
    }

    private func text(of action: DownloadRowAction) -> Text {
        switch action {
        case .retry: Text("downloads.retry")
        case .resume: Text("downloads.resume")
        case .pause: Text("downloads.pause")
        case .moveEarlier: Text("downloads.moveEarlier \(download.title)")
        case .moveLater: Text("downloads.moveLater \(download.title)")
        case .stop: Text("downloads.stop")
        case .remove: Text("downloads.remove")
        }
    }

    /// Where this one has got to, said in whichever way is true of it.
    @ViewBuilder
    private var state: some View {
        switch download.state {
        case let .failed(reason, attempts):
            // The reason, in the reader's words, and how many times it was tried — the
            // "plain-language reason" half of `offline-downloads`' Failure scenario. The
            // "retry action" half is the button above, which this line used to stand in for.
            // The stored reason is a code; the words are chosen now, in the language the
            // reader has chosen now — `localization` 15.9.
            Text("downloads.failed \(DownloadFailureWords.sentence(stored: reason)) \(attempts)")
                .textRole(.footnote)
                .foregroundStyle(StoryArcColor.Status.danger)
        case let .paused(pause):
            Text(pause.explanationKey)
                .textRole(.footnote)
                .foregroundStyle(theme.palette.textSecondary)
        case .queued, .running, .finished:
            if let fraction = download.fraction {
                ProgressView(value: fraction)
                    // The line below states the same percentage and states the sizes as
                    // well, so a reader on VoiceOver would otherwise hear the figure
                    // twice — once with no units attached to it.
                    .accessibilityHidden(progress != nil)
            } else {
                // No size from the server, so no bar that could be honest about a
                // fraction. `offline-downloads` would rather show an indeterminate state
                // than a fabricated total.
                ProgressView()
            }
        }

        progressLine
        attemptLine
    }

    /// Whether the last attempt at this download carried a transfer on or started it over.
    ///
    /// `offline-downloads`' *Resuming after interruption* builds both outcomes and states
    /// neither on the row — `DownloadResumption.swift` and `BackgroundTransfers.swift`
    /// already do the resuming; this is only what a reader is told about it. Drawn only
    /// once there has been an attempt to say something about: a download still on its
    /// first try is neither, and saying so would be the noise every other conditional line
    /// on this row avoids.
    @ViewBuilder
    private var attemptLine: some View {
        if let attempt = download.lastAttempt {
            Text(attempt.rowKey)
                .textRole(.footnote)
                .foregroundStyle(theme.palette.textSecondary)
        }
    }

    /// How far through, and how much of what — the half of `offline-downloads` the bar
    /// alone cannot carry.
    ///
    /// The spec asks a queued publication to have "its size shown, and progress visible on
    /// the publication and in a single downloads view". The row had the bar and nothing
    /// else, so the September sweep photographed three transfers stating no size and no
    /// percentage between them. A bar answers *roughly how far*; the question a reader with
    /// 400 MB free is actually asking is *how much*.
    ///
    /// Under the bar rather than beside the title, because it changes while a reader is
    /// looking at it and a number on the first line is a number that makes the title jump.
    ///
    /// What there is to say is ``LibraryFeature/DownloadQueueProgress``'s and is pinned by
    /// its own tests. Only the rendering is here, because the strings are in this bundle.
    private var progress: DownloadQueueProgress.Statement? {
        DownloadQueueProgress.statement(for: download)
    }

    @ViewBuilder
    private var progressLine: some View {
        if let progress {
            Group {
                switch progress {
                case let .sized(percent, downloaded, expected):
                    Text("downloads.progress \(percent) \(size(downloaded)) \(size(expected))")
                case let .unsized(downloaded):
                    Text("downloads.progress.unsized \(size(downloaded))")
                }
            }
            .textRole(.footnote)
            .foregroundStyle(theme.palette.textSecondary)
        }
    }

    /// A byte count as a person reads it, through the app's one helper for it.
    ///
    /// ``Persistence/DownloadStore/formatted(_:)``, so a transfer that has not started yet
    /// reads "0 bytes of 41 MB" and the total at the foot of this same screen reads
    /// "0 bytes" too, rather than "Zero kB".
    private func size(_ bytes: Int64) -> String {
        DownloadStore.formatted(bytes)
    }
}

extension DownloadRowAction {
    fileprivate var symbol: String {
        switch self {
        case .retry: "arrow.clockwise"
        case .resume: "play"
        case .pause: "pause"
        case .moveEarlier: "chevron.up"
        case .moveLater: "chevron.down"
        case .stop: "xmark"
        case .remove: "trash"
        }
    }
}
