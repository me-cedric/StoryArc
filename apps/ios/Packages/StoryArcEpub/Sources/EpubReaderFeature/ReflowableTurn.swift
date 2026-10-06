internal import SwiftUI
internal import UIKit

internal import ReadiumNavigator
internal import ReadiumShared
public import StoryArcCore

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
    /// Which page-turn rows to offer, and which of them this content cannot run.
    ///
    /// Beside the turns it decides rather than on the model, which is at the line cap
    /// `scripts/line-cap.mjs` holds. That is the better place for it anyway: this file
    /// already holds ``drawnTurn``, which reads nothing else, and a reader of either has to
    /// read both. Android's `transitions(reduceMotion:)` sits beside its own twin for the
    /// same two reasons.
    ///
    /// - Parameter reduceMotion: read from the environment by the view, because that is
    ///   where a SwiftUI accessibility setting lives and where a change to it arrives.
    public func transitions(reduceMotion: Bool) -> TransitionChoices {
        TransitionChoices(
            chosen: transition,
            // Reflowing text scrolls the way it is read; the axis is not a choice here.
            axis: .vertical,
            reduceMotion: reduceMotion,
            // D11's refusal, about this device rather than this content: a device that
            // dropped frames on its first curls keeps the choice and loses the mode. The
            // reader is told which of the two refusals they met.
            canCurl: !CurlCapability().cannotCurl,
            // Both true, because this reader takes the turn over for both:
            // `turnWithFade(forward:)` moves the navigator under a still and dips through
            // the page colour, and `turnWithCurl(forward:)` photographs the page either
            // side of the move and rolls the first off the second (task 8.12). The live web
            // content is back the moment either ends.
            canFade: true,
            canCurlOverText: true,
            isReflowable: true
        )
    }

    /// The transition StoryArc itself draws over this page, or `nil` where Readium keeps the
    /// turn.
    ///
    /// `effective`, not `transition`, which left Slide animating under Readium even with
    /// Reduce Motion on. Two modes answer now: Fast fade, which needs the one raster it takes
    /// before the navigator moves, and Curl, which needs the second one `turnWithCurl`
    /// takes after it.
    var drawnTurn: PageTransition? {
        switch transitions(reduceMotion: reduceMotion).effective {
        case .fastFade: .fastFade
        case .pageCurl: .pageCurl
        default: nil
        }
    }

    /// Whether StoryArc draws the turn rather than Readium.
    var ownsTheTurn: Bool { drawnTurn != nil }

    /// Whether Readium has resolved this publication's progression to right-to-left.
    ///
    /// `navigator.settings` is Readium's own resolved answer — publisher metadata, then
    /// the publication's language, then the app default — so this reader never guesses at
    /// a rule Readium already owns. Task 9.12: the edge taps, the arrow keys and the Fast
    /// fade swipe are screen-spatial, and Readium's own pagination is the only place that
    /// already knows which way the book reads.
    var isRightToLeft: Bool { navigator?.settings.readingProgression == .rtl }
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
    ///
    /// - Parameter isRightToLeft: mirrors the band, the way the comic reader's own display
    ///   order already mirrors its edge taps for free (`ZoomablePage`). This reader has no
    ///   display-order layer — Readium paginates the text — so the mirror happens here, at
    ///   the one place a screen position turns into a logical forward/backward call.
    static func outcome(x: CGFloat, width: CGFloat, tapTurnsPages: Bool, isRightToLeft: Bool = false) -> Bool? {
        guard tapTurnsPages else { return nil }
        let band = width * edgeFraction
        if x < band { return isRightToLeft }
        if x > width - band { return !isRightToLeft }
        return nil
    }
}

/// Which way a finished Fast fade swipe turns: `true` forward, `false` back, and `nil` for a
/// swipe too short to mean a turn. Android's `TurnDrag.direction` is the same rule.
enum TurnDrag {
    /// Enough travel to mean a turn rather than a stray finger. The threshold is exclusive.
    static let threshold: CGFloat = 40

    /// A leftward swipe turns forward in a left-to-right book. A right-to-left book mirrors
    /// it, as ``EdgeTap`` mirrors the band.
    static func direction(travel: CGFloat, isRightToLeft: Bool) -> Bool? {
        guard abs(travel) > threshold else { return nil }
        return (travel < 0) != isRightToLeft
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
    /// Whether Readium has resolved this book's progression to right-to-left. Mirrors the
    /// edge-tap band, the pan and the arrow keys. See ``EpubReaderModel/isRightToLeft``.
    private var isRightToLeft = false

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
                guard let self, let key = EpubTurnKey.outcome(for: event, isRightToLeft: isRightToLeft) else {
                    return false
                }
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
        isRightToLeft: Bool = false,
        on view: UIView
    ) {
        self.turn = turn
        self.animatedTurn = animatedTurn
        self.reveal = reveal
        self.tapTurnsPages = tapTurnsPages
        self.isRightToLeft = isRightToLeft
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
        if let forward = EdgeTap.outcome(
            x: x, width: width, tapTurnsPages: tapTurnsPages, isRightToLeft: isRightToLeft
        ) {
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
        guard let forward = TurnDrag.direction(travel: travel, isRightToLeft: isRightToLeft) else { return }
        turn?(forward)
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
