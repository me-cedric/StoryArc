public import SwiftUI

internal import DesignSystem

/// What the reader says when the network has gone quiet.
///
/// `network-share` is precise about the timing: an indicator appears "only if a page is
/// actually blocked on the network for more than 2 seconds", and after 60 seconds of failure
/// the app "offers to download the current publication for offline reading […] and to return
/// to the library". A brief stall says nothing, because a brief stall is not news.
///
/// The reader knows nothing about SMB. It is handed a way to ask when trouble started and
/// decides what to show; the app layer is what answers from whichever source produced it.
struct NetworkNotice: View {
    @Environment(\.theme) private var theme

    /// Asked once a second. A closure rather than a value because the source of truth lives
    /// in another module, and `ReaderFeature` depending on it would point the arrow wrong.
    let blockedSince: () -> Date?
    let onDismiss: () -> Void
    /// Answers whether the copy started. `network-share`'s offer does not disappear on a
    /// `false`: the share is still down, which is the very reason the offer exists, so the
    /// reader is told the attempt failed rather than left to wonder why nothing happened.
    let onDownload: (() async -> Bool)?
    let onLeave: () -> Void

    @State private var blocked: TimeInterval = 0
    @State private var dismissed: NoticeStage?
    @State private var downloadFailed = false
    @State private var isCopying = false

    var body: some View {
        Group {
            if let stage = NoticeStage.of(blocked: blocked, dismissed: dismissed) {
                notice(stage)
            }
        }
        .task {
            // A ticking clock, because the notice's whole content is a function of elapsed
            // time and nothing else changes to trigger a redraw.
            while !Task.isCancelled {
                if let since = blockedSince() {
                    blocked = Date().timeIntervalSince(since)
                } else {
                    blocked = 0
                    dismissed = nil
                    downloadFailed = false
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    @ViewBuilder
    private func notice(_ stage: NoticeStage) -> some View {
        let isLong = stage == .long
        let message = isLong
            ? String(localized: "reader.offline.long", bundle: .module, locale: .storyArc)
            : String(localized: "reader.offline.brief", bundle: .module, locale: .storyArc)

        VStack(alignment: .leading, spacing: StoryArcSpace.xs) {
            Text(message)
                .textRole(.body)
                .foregroundStyle(theme.palette.textPrimary)

            // Answers "why did nothing happen" for the one action here that can fail
            // without a page turn or a dismissal to say so on its own.
            if downloadFailed {
                Text("reader.offline.download.failed", bundle: .module)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textPrimary)
            }

            HStack(spacing: StoryArcSpace.md) {
                if isLong, let onDownload {
                    Button {
                        downloadFailed = false
                        isCopying = true
                        Task {
                            downloadFailed = !(await onDownload())
                            isCopying = false
                        }
                    } label: {
                        Text("reader.offline.download", bundle: .module)
                    }
                    .disabled(isCopying)
                }
                if isLong {
                    Button(action: onLeave) {
                        Text("reader.offline.leave", bundle: .module)
                    }
                }
                Button { dismissed = stage; onDismiss() } label: {
                    Text("reader.offline.dismiss", bundle: .module)
                }
            }
            .textRole(.footnote)
        }
        .padding(StoryArcSpace.md)
        .background(theme.palette.surfaceRaised, in: .rect(cornerRadius: StoryArcRadius.md))
        .padding(StoryArcSpace.gutter)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(message)
    }
}

/// Which of the two notices the reader is owed, if either.
///
/// Lifted beside ``NetworkNotice`` so a test can hold the rule. A dismissal hides the stage it
/// was made on and nothing later: the reader who dismisses the 2 s notice is still offered the
/// download at 60 s, and the reader who dismisses the offer hears nothing more until the
/// trouble ends. Android's `NoticeStage` is the same rule.
enum NoticeStage: Equatable {
    case brief
    case long

    /// `network-share`: "more than 2 seconds".
    static let noticeAfter: TimeInterval = 2

    /// `network-share`: "longer than 60 seconds".
    static let offerAfter: TimeInterval = 60

    static func of(blocked: TimeInterval, dismissed: NoticeStage?) -> NoticeStage? {
        let stage: NoticeStage
        if blocked >= offerAfter {
            stage = .long
        } else if blocked >= noticeAfter {
            stage = .brief
        } else {
            return nil
        }
        return dismissed == .long || dismissed == stage ? nil : stage
    }
}
