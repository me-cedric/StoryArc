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
/// **Stop, reorder, and not yet pause.** The two controls here are the two the app can
/// honestly offer from this screen: the order and the record are the download store's, and
/// this writes them. Pause and resume are the running ``LibraryFeature/DownloadQueue``'s,
/// and that object lives with the catalogue browser that started the transfer — a button
/// here would write "paused" into the record while the bytes kept arriving. Lifting the
/// queue to the app layer is its own change; a control that lies is worse than one that is
/// missing.
struct DownloadQueueSection: View {
    @Environment(\.theme) private var theme

    /// Active, queued and failed, in the order they will be worked through.
    let downloads: [Download]

    /// Moves a queued download one place; `true` is later.
    let onReorder: (Download, Bool) -> Void

    /// Takes one out of the queue altogether, confirmed by the caller.
    let onStop: (Download) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.md) {
            Text("downloads.inFlight")
                .textRole(.title3)
                .foregroundStyle(theme.palette.textPrimary)
                .padding(.horizontal, StoryArcSpace.gutter)

            VStack(spacing: StoryArcSpace.sm) {
                ForEach(downloads) { download in
                    DownloadQueueRow(
                        download: download,
                        // Only a queued download has an order to change: a running one has
                        // started, and the list is short enough that its ends are obvious.
                        canReorder: download.state == .queued,
                        onReorder: { onReorder(download, $0) },
                        onStop: { onStop(download) }
                    )
                }
            }
            .padding(.horizontal, StoryArcSpace.gutter)
        }
    }
}

/// One transfer: what it is, where it has got to, and the two things a reader can do to it.
private struct DownloadQueueRow: View {
    @Environment(\.theme) private var theme

    /// At the accessibility sizes the title and its three controls cannot share a line:
    /// the title truncates to two characters while *Stop* wraps to two lines, which is
    /// neither readable nor tappable. Above the threshold the row becomes two.
    @Environment(\.dynamicTypeSize) private var typeSize

    let download: Download
    let canReorder: Bool
    let onReorder: (Bool) -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.xs) {
            if typeSize.isAccessibilitySize {
                title.lineLimit(3)
                HStack(spacing: StoryArcSpace.sm) { controls }
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

    /// Reorder, where there is an order to change, and stop.
    @ViewBuilder
    private var controls: some View {
        if canReorder {
            reorder(later: false, symbol: "chevron.up")
            reorder(later: true, symbol: "chevron.down")
        }

        Button(role: .destructive, action: onStop) {
            Text("downloads.stop").lineLimit(1)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    /// Where this one has got to, said in whichever way is true of it.
    @ViewBuilder
    private var state: some View {
        switch download.state {
        case let .failed(reason, attempts):
            // The reason, in the reader's words, and how many times it was tried.
            // `offline-downloads` requires "a plain-language reason and a retry action";
            // the retry belongs to the running queue, which is why the count is shown
            // rather than hidden behind a button that cannot reach it.
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

    /// A byte count as a person reads it.
    ///
    /// `spellsOutZero: false`, which is the app's one way of writing a size — see
    /// ``SettingsFeature/PrivacySettings``. A transfer that has not started yet reads
    /// "0 bytes of 41 MB", never "Zero kB of 41 MB".
    private func size(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file, spellsOutZero: false))
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

extension Download.Pause {
    /// Why this one is not moving, in the reader's terms.
    ///
    /// The app target's own copy of the mapping `SettingsFeature` carries, because the
    /// strings are in this bundle now: the queue moved out of Settings, and a key looked up
    /// in the wrong bundle renders as the key.
    var explanationKey: LocalizedStringKey {
        switch self {
        case .byReader: "downloads.paused.byReader"
        case .waitingForWiFi: "downloads.paused.waitingForWiFi"
        case .outOfSpace: "downloads.paused.outOfSpace"
        }
    }
}
