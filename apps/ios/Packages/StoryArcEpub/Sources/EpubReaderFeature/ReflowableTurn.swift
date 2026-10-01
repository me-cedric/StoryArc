internal import SwiftUI
internal import UIKit

internal import ReadiumNavigator

// Taking the page turn over from Readium, so a transition StoryArc draws can run over
// reflowable text.
//
// `page-transitions` offers four modes and an EPUB could only ever do two of them. The
// reason was never the shader: it is that Readium owns the turn. Slide is Readium's own
// paginated scroll, `EpubReaderModel.goForward()` had no callers, and nothing in StoryArc
// was ever holding a turn at a fraction between two pages.
//
// Apple Books does curl over reflowable text, so the approach is proven. This is the first
// half of it: one raster, one cross-fade, which is Fast fade. Curl needs the *incoming*
// page as a second texture before it is on screen, and that is a separate problem.

/// Readium's paginated scroll view, found by walking the hierarchy.
///
/// `PaginationView.isScrollEnabled` is internal to ReadiumNavigator, so there is no API
/// for this. What is public is `UIScrollView`, and the paginated container is the only one
/// inside the navigator with paging switched on — which is a narrow enough description to
/// find it by.
///
/// ponytail: relies on Readium's view structure rather than its API, so a Readium upgrade
/// can move it. That is why every caller treats `nil` as "keep Readium's own turn" instead
/// of failing: the ceiling here is a lost transition, never a reader who cannot turn a
/// page.
enum PaginatedScroll {
    static func find(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView, scroll.isPagingEnabled { return scroll }
        for subview in view.subviews {
            if let found = find(in: subview) { return found }
        }
        return nil
    }
}

extension EpubReaderModel {
    /// Whether StoryArc draws the turn rather than Readium. True for Fast fade itself,
    /// and for Slide once Reduce Motion has substituted it — `effective`, not `transition`,
    /// which left Slide animating under Readium even with Reduce Motion on.
    var ownsTheTurn: Bool { transitions(reduceMotion: reduceMotion).effective == .fastFade }
}

/// The gestures Readium is no longer handling, plus the edge-tap turn Readium never had.
///
/// The tap recogniser is installed always, in every page-turn mode. `page-transitions`
/// makes edge-third taps a reader setting, not something Fast fade alone offers — before
/// this, a reader who left the default Slide chosen had no tap zones at all, because this
/// type installed nothing until Fast fade owned the turn. The pan recogniser stays scoped
/// to that one mode: disabling Readium's scroll takes the swipe away, and a reader who
/// chose Fast fade should not also lose swiping, but Slide and Scroll still need
/// Readium's own scroll view for their own gesture.
@MainActor
final class TurnGestures: NSObject {
    /// Non-nil only while Fast fade owns the turn. See ``EpubReaderModel/ownsTheTurn``.
    private var turn: ((Bool) -> Void)?
    /// Readium's own, animated turn — used for an edge tap wherever Fast fade is not
    /// chosen, so Slide and Scroll answer a tap the same way the comic reader answers one.
    private var animatedTurn: ((Bool) -> Void)?
    private var reveal: (() -> Void)?
    /// Whether a tap in an edge band turns the page at all.
    ///
    /// `page-transitions` makes the zones a setting, and this reader ignored it: a reader
    /// who turned *Tapping the page turns it* off, opened an EPUB and chose Fast fade
    /// still turned pages by tapping, while the comic reader beside it obeyed. The comic
    /// reader takes the flag from the environment; this package cannot see that key, and
    /// it does not need to — ``EpubReaderView`` already holds the settings.
    private var tapTurnsPages = true
    /// A third of the width, which is the comic reader's own band.
    ///
    /// It was a quarter, which left half the screen doing nothing but revealing the
    /// chrome and disagreed with `page-transitions`' "each zone is a third of the
    /// screen's width". `ZoomablePage.edgeZoneFraction` is the same number in the other
    /// package, and `ReaderTapZonesTests` is where the two are held together.
    private static let edgeFraction: CGFloat = 1.0 / 3.0
    /// Enough travel to mean a turn rather than a stray finger.
    private static let panThreshold: CGFloat = 40

    private var tapRecogniser: UITapGestureRecognizer?
    private var panRecogniser: UIPanGestureRecognizer?
    private weak var host: UIView?
    /// Whether the pan is currently installed and Readium's own scroll currently stopped.
    private var ownsTurn = false

    /// Takes the turn over, or hands it back. Installs the tap once, on the first host.
    ///
    /// Called on every update rather than once at creation, because a reader chooses a
    /// page turn *after* the book is open. Idempotent: the same mode twice changes
    /// nothing, and switching back to Slide gives Readium its scroll and its swipe — the
    /// tap stays either way, because Slide has tap zones of its own now.
    func apply(
        turn: ((Bool) -> Void)?,
        animatedTurn: @escaping (Bool) -> Void,
        reveal: @escaping () -> Void,
        tapTurnsPages: Bool,
        on view: UIView
    ) {
        self.turn = turn
        self.animatedTurn = animatedTurn
        self.reveal = reveal
        self.tapTurnsPages = tapTurnsPages

        if host !== view {
            if let tapRecogniser, let host { host.removeGestureRecognizer(tapRecogniser) }
            if let panRecogniser, let host { host.removeGestureRecognizer(panRecogniser) }
            panRecogniser = nil
            ownsTurn = false
            host = view

            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
            tap.delegate = self
            view.addGestureRecognizer(tap)
            tapRecogniser = tap
        }

        let shouldOwn = turn != nil
        guard shouldOwn != ownsTurn else { return }
        ownsTurn = shouldOwn

        // Readium's paginated scroll is what animates a Slide, so it has to stop for a
        // transition StoryArc draws — otherwise both run and the page slides *and* fades.
        // If it cannot be found, Readium keeps the turn and the reader gets a Slide, which
        // is a lost transition rather than a reader who cannot turn a page.
        PaginatedScroll.find(in: view)?.isScrollEnabled = !shouldOwn

        if shouldOwn {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(panned))
            pan.delegate = self
            view.addGestureRecognizer(pan)
            panRecogniser = pan
        } else if let panRecogniser {
            view.removeGestureRecognizer(panRecogniser)
            self.panRecogniser = nil
        }
    }

    @objc private func tapped(_ recogniser: UITapGestureRecognizer) {
        let view = recogniser.view ?? UIView()
        let point = recogniser.location(in: view)
        let band = view.bounds.width * Self.edgeFraction
        // `page-transitions`: with the zones off "a tap anywhere toggles the chrome, and
        // no tap turns a page". Not "no tap does anything" — the way back to the menu is
        // the one thing a reader still needs from a tap. Fast fade's own turn wins over
        // Readium's animated one where both exist; outside Fast fade only the latter does.
        if tapTurnsPages, point.x < band {
            (turn ?? animatedTurn)?(false)
        } else if tapTurnsPages, point.x > view.bounds.width - band {
            (turn ?? animatedTurn)?(true)
        } else {
            reveal?()
        }
    }

    @objc private func panned(_ recogniser: UIPanGestureRecognizer) {
        guard recogniser.state == .ended else { return }
        let travel = recogniser.translation(in: recogniser.view).x
        guard abs(travel) > Self.panThreshold else { return }
        // Dragging leftwards moves forwards, the way every paginated reader behaves.
        turn?(travel < 0)
    }
}

extension TurnGestures: @MainActor UIGestureRecognizerDelegate {
    /// Alongside whatever else is listening.
    ///
    /// Readium keeps its own recognisers for selection and for links even with its scroll
    /// disabled, and a reader still has to be able to select a word.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool { true }
}
