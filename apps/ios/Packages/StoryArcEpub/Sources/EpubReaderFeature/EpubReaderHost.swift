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
/// The tap and the turn keys are registered through Readium's own input observers rather
/// than a SwiftUI gesture: a gesture layered over the web view swallows the taps the
/// reader needs to turn pages and follow links. See ``TurnGestures``.
struct NavigatorHost: UIViewControllerRepresentable {
    let navigator: EPUBNavigatorViewController
    /// Non-nil when StoryArc draws the turn. See ``EpubReaderModel/ownsTheTurn``.
    let turn: ((Bool) -> Void)?
    /// Readium's own, animated turn — what an edge tap and the turn keys fall back to
    /// outside Fast fade, so Slide and Scroll turn pages too rather than only revealing.
    let animatedTurn: (Bool) -> Void
    /// Whether an edge tap turns the page. `page-transitions` makes it a reader's setting.
    let tapTurnsPages: Bool
    /// Mirrors the edge-tap band and the Fast fade swipe. Task 9.12.
    var isRightToLeft: Bool = false
    let onTap: () -> Void

    func makeUIViewController(context: Context) -> EPUBNavigatorViewController {
        context.coordinator.observe(navigator)
        return navigator
    }

    static func dismantleUIViewController(_ controller: EPUBNavigatorViewController, coordinator: TurnGestures) {
        coordinator.stopObserving(controller)
    }

    func makeCoordinator() -> TurnGestures { TurnGestures() }

    /// Where the turn changes hands.
    ///
    /// Not `makeUIViewController`: that runs once, when the reader opens, and the reader
    /// picks a page turn afterwards. Installing there meant the gestures were only ever
    /// set up for whatever mode the book happened to open in — so choosing Fast fade did
    /// nothing at all, which is exactly how this was found.
    func updateUIViewController(_ controller: EPUBNavigatorViewController, context: Context) {
        context.coordinator.apply(
            turn: turn,
            animatedTurn: animatedTurn,
            reveal: onTap,
            tapTurnsPages: tapTurnsPages,
            isRightToLeft: isRightToLeft,
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
