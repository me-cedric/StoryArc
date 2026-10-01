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
/// The tap is registered through ``TurnGestures``, a plain `UIGestureRecognizer`, rather
/// than a SwiftUI gesture: a gesture layered over the web view swallows the taps the
/// reader needs to turn pages and follow links, where a recogniser added directly to the
/// navigator's own view — and set to recognise simultaneously with whatever else is
/// listening — does not.
struct NavigatorHost: UIViewControllerRepresentable {
    let navigator: EPUBNavigatorViewController
    /// Non-nil when StoryArc draws the turn. See ``EpubReaderModel/ownsTheTurn``.
    let turn: ((Bool) -> Void)?
    /// Readium's own, animated turn — what an edge tap and the turn keys fall back to
    /// outside Fast fade, so Slide and Scroll turn pages too rather than only revealing.
    let animatedTurn: (Bool) -> Void
    /// Whether an edge tap turns the page. `page-transitions` makes it a reader's setting.
    let tapTurnsPages: Bool
    let onTap: () -> Void

    func makeUIViewController(context: Context) -> EPUBNavigatorViewController { navigator }

    func makeCoordinator() -> TurnGestures { TurnGestures() }

    /// Where the turn changes hands.
    ///
    /// Not `makeUIViewController`: that runs once, when the reader opens, and the reader
    /// picks a page turn afterwards. Installing there meant the gestures were only ever
    /// set up for whatever mode the book happened to open in — so choosing Fast fade did
    /// nothing at all, which is exactly how this was found. ``TurnGestures`` installs its
    /// tap recogniser the first time this runs, which covers the book's opening mode too.
    func updateUIViewController(_ controller: EPUBNavigatorViewController, context: Context) {
        context.coordinator.apply(
            turn: turn,
            animatedTurn: animatedTurn,
            reveal: onTap,
            tapTurnsPages: tapTurnsPages,
            on: controller.view
        )
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
