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
    let onDownload: (() -> Void)?
    let onLeave: () -> Void

    @State private var blocked: TimeInterval = 0
    @State private var isDismissed = false

    /// `network-share`: "more than 2 seconds".
    private let noticeAfter: TimeInterval = 2

    /// `network-share`: "longer than 60 seconds".
    private let offerAfter: TimeInterval = 60

    var body: some View {
        Group {
            if blocked >= noticeAfter, !isDismissed {
                notice
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
                    isDismissed = false
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var isLong: Bool { blocked >= offerAfter }

    @ViewBuilder
    private var notice: some View {
        let message = isLong
            ? String(localized: "reader.offline.long", bundle: .module)
            : String(localized: "reader.offline.brief", bundle: .module)

        VStack(alignment: .leading, spacing: StoryArcSpace.xs) {
            Text(message)
                .textRole(.body)
                .foregroundStyle(theme.palette.textPrimary)

            HStack(spacing: StoryArcSpace.md) {
                if isLong, let onDownload {
                    Button(action: onDownload) {
                        Text("reader.offline.download", bundle: .module)
                    }
                }
                if isLong {
                    Button(action: onLeave) {
                        Text("reader.offline.leave", bundle: .module)
                    }
                }
                Button { isDismissed = true; onDismiss() } label: {
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
