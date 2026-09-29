#if os(iOS)
internal import UIKit

// The horizontal swipe that turns a page in Fast fade (task 8.2). Split out of
// `ZoomablePage.swift`, which is near the 400-line cap. A UIKit pan rather than a
// SwiftUI drag for the reason the taps are UIKit: a second kind of recogniser over the
// scroll view competes with it. The reflowable reader's `ReflowableTurn` makes the same
// choice.
extension ScrollingPage {

    /// Installed only where a container asked for it. Slide's pager and the curl own the
    /// swipe themselves, and a second turn from the same finger would skip a page.
    func addSwipe(to scrollView: UIScrollView, coordinator: Coordinator) {
        guard onSwipe != nil else { return }
        let pan = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleSwipe(_:)))
        pan.delegate = coordinator
        scrollView.addGestureRecognizer(pan)
        coordinator.swipe = pan
    }
}

extension ScrollingPage.Coordinator {

    /// Turns the page when the finger lifts, by ``fadeSwipeStep(travel:threshold:)``.
    @objc func handleSwipe(_ recogniser: UIPanGestureRecognizer) {
        guard recogniser.state == .ended, let view = recogniser.view else { return }
        let step = fadeSwipeStep(travel: recogniser.translation(in: view).x)
        if step != 0 { onSwipe?(step) }
    }

    /// The swipe starts only across a page with no room to pan sideways, so a reader who
    /// zoomed in pans the page rather than turning it. Every other recogniser starts as before.
    func gestureRecognizerShouldBegin(_ recogniser: UIGestureRecognizer) -> Bool {
        guard recogniser === swipe, let pan = swipe, let scrollView = pan.view as? UIScrollView else {
            return true
        }
        let velocity = pan.velocity(in: scrollView)
        let hasSlack = scrollView.contentSize.width > scrollView.bounds.width + 1
        return !hasSlack && abs(velocity.x) > abs(velocity.y)
    }

    /// With the scroll view's own pan, so a fit-to-width page still scrolls down while the
    /// finger also moves sideways.
    func gestureRecognizer(
        _ recogniser: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        recogniser === swipe || other === swipe
    }
}
#endif
