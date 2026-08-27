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

/// The gestures Readium is no longer handling.
///
/// Installed only while StoryArc owns the turn. A horizontal pan and an edge tap, because
/// disabling Readium's scroll takes the swipe away and a reader who chose Fast fade should
/// not also lose swiping.
@MainActor
final class TurnGestures: NSObject {
    private var turn: ((Bool) -> Void)?
    private var reveal: (() -> Void)?
    /// A quarter of the width, matching the comic reader's own edge-tap band.
    private static let edgeFraction: CGFloat = 0.25
    /// Enough travel to mean a turn rather than a stray finger.
    private static let panThreshold: CGFloat = 40

    private var installed: [UIGestureRecognizer] = []
    private weak var host: UIView?

    /// Takes the turn over, or hands it back.
    ///
    /// Called on every update rather than once at creation, because a reader chooses a
    /// page turn *after* the book is open. Idempotent: the same mode twice changes
    /// nothing, and switching back to Slide gives Readium its scroll and its swipe.
    func apply(turn: ((Bool) -> Void)?, reveal: @escaping () -> Void, on view: UIView) {
        let shouldOwn = turn != nil
        guard shouldOwn != !installed.isEmpty || host !== view else {
            self.turn = turn
            self.reveal = reveal
            return
        }
        self.turn = turn
        self.reveal = reveal
        host = view

        for recogniser in installed { view.removeGestureRecognizer(recogniser) }
        installed = []

        // Readium's paginated scroll is what animates a Slide, so it has to stop for a
        // transition StoryArc draws — otherwise both run and the page slides *and* fades.
        // If it cannot be found, Readium keeps the turn and the reader gets a Slide, which
        // is a lost transition rather than a reader who cannot turn a page.
        PaginatedScroll.find(in: view)?.isScrollEnabled = !shouldOwn
        guard shouldOwn else { return }

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned))
        for recogniser in [tap, pan] as [UIGestureRecognizer] {
            recogniser.delegate = self
            view.addGestureRecognizer(recogniser)
            installed.append(recogniser)
        }
    }

    @objc private func tapped(_ recogniser: UITapGestureRecognizer) {
        let view = recogniser.view ?? UIView()
        let point = recogniser.location(in: view)
        let band = view.bounds.width * Self.edgeFraction
        if point.x < band {
            turn?(false)
        } else if point.x > view.bounds.width - band {
            turn?(true)
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
