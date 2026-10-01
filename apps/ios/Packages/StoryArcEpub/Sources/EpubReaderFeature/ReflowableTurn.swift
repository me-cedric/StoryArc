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

/// What a tap means, by where it landed: `true` turns forward, `false` turns back, and
/// `nil` reveals the chrome.
///
/// A plain function so the rule is testable with no navigator and no touch. Android's
/// `EdgeTap.outcome` is the same rule.
enum EdgeTap {
    /// A third of the width, which is the comic reader's own band.
    ///
    /// It was a quarter, which left half the screen doing nothing but revealing the
    /// chrome and disagreed with `page-transitions`' "each zone is a third of the
    /// screen's width". `ZoomablePage.edgeZoneFraction` is the same number in the other
    /// package, and `ReaderTapZonesTests` is where the two are held together.
    static let edgeFraction: CGFloat = 1.0 / 3.0

    /// `page-transitions`: with the zones off "a tap anywhere toggles the chrome, and no
    /// tap turns a page". Not "no tap does anything" — the way back to the menu is the one
    /// thing a reader still needs from a tap.
    static func outcome(x: CGFloat, width: CGFloat, tapTurnsPages: Bool) -> Bool? {
        guard tapTurnsPages else { return nil }
        let band = width * edgeFraction
        if x < band { return false }
        if x > width - band { return true }
        return nil
    }
}

/// The reader's taps, keys and — while Fast fade owns the turn — its swipe.
///
/// **Taps and keys come through Readium's own input observers**, in every page-turn mode.
/// Readium leaves out a tap on a link or another interactive element, so following a link
/// near the edge of the page does not also turn it. It also hears a key wherever the
/// focus is: the navigator takes the first responder when it appears, and a web view that
/// takes it later hands its key events to the same observers.
///
/// **The pan is StoryArc's own, and only for Fast fade.** Readium's paginated scroll is
/// what animates a Slide, so it has to stop for a transition StoryArc draws. Stopping it
/// takes the swipe away, and a reader who chose Fast fade should not also lose swiping.
@MainActor
final class TurnGestures: NSObject {
    /// Non-nil only while Fast fade owns the turn. See ``EpubReaderModel/ownsTheTurn``.
    private var turn: ((Bool) -> Void)?
    /// Readium's own, animated turn — used wherever Fast fade is not drawing the turn, so
    /// Slide and Scroll answer a tap or a key the same way the comic reader does.
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
    /// Enough travel to mean a turn rather than a stray finger.
    private static let panThreshold: CGFloat = 40

    private var pan: UIPanGestureRecognizer?
    private weak var host: UIView?
    private var observers: [InputObservableToken] = []

    /// Listens to Readium's taps, clicks and keys. Once per navigator: a second set would
    /// turn two pages for one tap.
    func observe(_ navigator: EPUBNavigatorViewController) {
        observers = [
            navigator.addObserver(.activate { [weak self, weak navigator] event in
                guard let self, let navigator else { return false }
                self.tapped(at: event.location.x, width: navigator.view.bounds.width)
                return true
            }),
            navigator.addObserver(.key { [weak self] event in
                guard let self, let key = EpubTurnKey.outcome(for: event) else { return false }
                self.pressed(key)
                return true
            }),
        ]
    }

    func stopObserving(_ navigator: EPUBNavigatorViewController) {
        for token in observers { navigator.removeObserver(token) }
        observers = []
    }

    /// Takes the swipe over, or hands it back.
    ///
    /// Called on every update rather than once at creation, because a reader chooses a
    /// page turn *after* the book is open. Idempotent: the same mode twice changes
    /// nothing, and switching back to Slide gives Readium its scroll and its swipe.
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
        let shouldOwn = turn != nil
        guard shouldOwn != (pan != nil) || host !== view else { return }

        if let pan { pan.view?.removeGestureRecognizer(pan) }
        pan = nil
        host = view

        // If the scroll cannot be found, Readium keeps the turn and the reader gets a
        // Slide, which is a lost transition rather than a reader who cannot turn a page.
        PaginatedScroll.find(in: view)?.isScrollEnabled = !shouldOwn
        guard shouldOwn else { return }

        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned))
        pan.delegate = self
        view.addGestureRecognizer(pan)
        self.pan = pan
    }

    /// Fast fade's own turn where it owns the turn, Readium's animated one elsewhere.
    func tapped(at x: CGFloat, width: CGFloat) {
        if let forward = EdgeTap.outcome(x: x, width: width, tapTurnsPages: tapTurnsPages) {
            (turn ?? animatedTurn)?(forward)
        } else {
            reveal?()
        }
    }

    func pressed(_ key: EpubTurnKey) {
        switch key {
        case .forward: (turn ?? animatedTurn)?(true)
        case .backward: (turn ?? animatedTurn)?(false)
        case .toggleChrome: reveal?()
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
