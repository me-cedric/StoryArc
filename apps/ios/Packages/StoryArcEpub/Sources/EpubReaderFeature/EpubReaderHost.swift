internal import SwiftUI

internal import ReadiumNavigator
internal import UIKit

internal import DesignSystem

// The two pieces of plumbing the reader screen stands on: the navigator inside a
// SwiftUI hierarchy, and what is shown when there is no navigator to show.
//
// Split out of `EpubReaderView` so that file stays the screen — the chrome, the sheets,
// the popovers — and this one stays the seam with UIKit. They change for different
// reasons, which is the only reason worth splitting on.

/// The navigator, in a SwiftUI hierarchy.
///
/// The tap is registered through Readium's own input observer rather than a
/// SwiftUI gesture: a gesture layered over the web view swallows the taps the
/// reader needs to turn pages and follow links.
struct NavigatorHost: UIViewControllerRepresentable {
    let navigator: EPUBNavigatorViewController
    /// Non-nil when StoryArc draws the turn. See ``EpubReaderModel/ownsTheTurn``.
    let turn: ((Bool) -> Void)?
    let onTap: () -> Void

    func makeUIViewController(context: Context) -> EPUBNavigatorViewController {
        // Readium's own tap, which reveals the chrome. Registered once and left alone:
        // when StoryArc owns the turn its own recogniser decides whether a tap is a turn
        // or a reveal, and calls this same closure for a reveal.
        navigator.addObserver(.tap { _ in
            onTap()
            return true
        })
        return navigator
    }

    func makeCoordinator() -> TurnGestures { TurnGestures() }

    /// Where the turn changes hands.
    ///
    /// Not `makeUIViewController`: that runs once, when the reader opens, and the reader
    /// picks a page turn afterwards. Installing there meant the gestures were only ever
    /// set up for whatever mode the book happened to open in — so choosing Fast fade did
    /// nothing at all, which is exactly how this was found.
    func updateUIViewController(_ controller: EPUBNavigatorViewController, context: Context) {
        context.coordinator.apply(turn: turn, reveal: onTap, on: controller.view)
    }
}

struct Failure: View {
    @Environment(\.theme) private var theme

    let message: String

    var body: some View {
        VStack(spacing: StoryArcSpace.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32, weight: .light))
            Text(message)
                .textRole(.footnote)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(theme.palette.textSecondary)
        .padding(StoryArcSpace.gutter)
    }
}
