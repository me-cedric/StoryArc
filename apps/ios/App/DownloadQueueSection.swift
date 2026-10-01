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
            // `ViewThatFits`, as the per-row controls below already use: three word-length
            // buttons beside the title share no line at the accessibility sizes, and a title
            // that is free to wrap is what keeps every button tappable there.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: StoryArcSpace.sm) {
                    title
                    Spacer(minLength: 0)
                    globalControls
                }
                VStack(alignment: .leading, spacing: StoryArcSpace.sm) {
                    title
                    globalControls
                }
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

    private var globalControls: some View {
        HStack(spacing: StoryArcSpace.sm) {
            Button(action: onPauseAll) { Text("downloads.pauseAll") }
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button(action: onResumeAll) { Text("downloads.resumeAll") }
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button(role: .destructive, action: onStopAll) { Text("downloads.cancelAll") }
                .buttonStyle(.bordered)
                .controlSize(.small)
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

    /// Puts this row back in the queue. Shown only for a row this reader paused: a row held
    /// for Wi-Fi or for space is put back by the connection or the space returning, and a
    /// control here would re-queue it only for the next `pump()` to pause it again for the
    /// same reason — a control that lies about what it did.
    let onResume: () -> Void

    let onStop: () -> Void
    let onRetry: () -> Void

    private var hasFailed: Bool {
        if case .failed = download.state { true } else { false }
    }

    private var isHeld: Bool {
        if case .paused = download.state { true } else { false }
    }

    /// A failed or held row is two lines at every size, because each carries two word-length
    /// buttons rather than one and the wider of the two is four times the width of *Stop* in
    /// every language this app speaks. It is the tallest row on the screen anyway — a reason
    /// sits under it — so the second line costs nothing it was not already spending. Android
    /// splits the same rows at every scale for the same reason.
    private var isStacked: Bool { hasFailed || isHeld || typeSize.isAccessibilitySize }

    var body: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.xs) {
            if isStacked {
                title.lineLimit(3)
                controls
            } else {
                HStack(spacing: StoryArcSpace.sm) {
                    title.lineLimit(1)
                    Spacer(minLength: 0)
                    controls
                }
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

    /// Retry and remove on a failure, resume and remove on a hold, reorder where there is an
    /// order to change plus pause and stop on everything else.
    @ViewBuilder
    private var controls: some View {
        if hasFailed {
            twoControls(first: retry, second: remove)
        } else if isHeld {
            twoControls(first: resumeButton, second: remove)
        } else {
            HStack(spacing: StoryArcSpace.sm) {
                if canReorder {
                    reorder(later: false, symbol: "chevron.up")
                    reorder(later: true, symbol: "chevron.down")
                }

                Button(action: onPause) {
                    Text("downloads.pause").lineLimit(1)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(role: .destructive, action: onStop) {
                    Text("downloads.stop").lineLimit(1)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    /// The first control named first, because it is the thing a reader opened this screen to
    /// do, and the second — always *Remove download* — beside it, or under it.
    ///
    /// Beside it at the ordinary sizes. At the accessibility sizes the two do not share a
    /// line even without the title: *Download entfernen* on its own is wider than the row at
    /// AccessibilityXXXL, so the pair goes one under the other and each label is free to
    /// wrap. Neither is ever truncated to a verb with no object, which is what a `lineLimit`
    /// would have made of the German.
    private func twoControls(first: some View, second: some View) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: StoryArcSpace.sm) {
                first
                second
            }
            VStack(alignment: .leading, spacing: StoryArcSpace.sm) {
                first
                second
            }
        }
    }

    private var retry: some View {
        Button(action: onRetry) {
            Text("downloads.retry")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var resumeButton: some View {
        Button(action: onResume) {
            Text("downloads.resume")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var remove: some View {
        Button(role: .destructive, action: onStop) {
            Text("downloads.remove")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    /// Where this one has got to, said in whichever way is true of it.
    @ViewBuilder
    private var state: some View {
        switch download.state {
        case let .failed(reason, attempts):
            // The reason, in the reader's words, and how many times it was tried — the
            // "plain-language reason" half of `offline-downloads`' Failure scenario. The
            // "retry action" half is the button above, which this line used to stand in for.
            Text("downloads.failed \(reason) \(attempts)")
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

    private func reorder(later: Bool, symbol: String) -> some View {
        Button {
            onReorder(later)
        } label: {
            Label {
                if later {
                    Text("downloads.moveLater \(download.title)")
                } else {
                    Text("downloads.moveEarlier \(download.title)")
                }
            } icon: {
                Image(systemName: symbol)
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .foregroundStyle(theme.palette.textSecondary)
    }
}
