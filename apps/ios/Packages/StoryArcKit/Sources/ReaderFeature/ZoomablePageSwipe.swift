internal import CoreGraphics

/// Whether a horizontal pan over a page turns it rather than panning it.
///
/// Only across a page no wider than the screen, so a reader who zoomed in pans the page
/// rather than turning it, and only for a finger moving more across than down, so a
/// fit-to-width page still scrolls. Fast fade's swipe and the curl's drag both start here.
func pagePanTurns(pageWidth: CGFloat, boundsWidth: CGFloat, velocity: CGPoint) -> Bool {
    let hasSlack = pageWidth > boundsWidth + 1
    return !hasSlack && abs(velocity.x) > abs(velocity.y)
}

/// How wide the page itself is drawn, which is not how wide the scroll content is.
///
/// The image view is the scroll view's bounds times the zoom, and the page is fitted inside
/// it. A page taller than the screen's shape, at fit-to-width, makes content wider than the
/// screen around a page exactly as wide as it — and that page has nothing to pan to.
func pageWidth(image: CGSize, bounds: CGSize, zoomScale: CGFloat) -> CGFloat {
    fitted(image, in: bounds).width * zoomScale
}

#if os(iOS)
internal import UIKit

// The horizontal swipe that turns a page in Fast fade (task 8.2), and the drag that turns it
// in Curl (task 8.16). Split out of `ZoomablePage.swift`, which is near the 400-line cap. A
// UIKit pan rather than a SwiftUI drag for the reason the taps are UIKit: a second kind of
// recogniser over the scroll view competes with it. The reflowable reader's `ReflowableTurn`
// makes the same choice.
extension ScrollingPage {

    /// Installed only where a container asked for it. Slide's pager owns the swipe itself,
    /// and a second turn from the same finger would skip a page.
    func addSwipe(to scrollView: UIScrollView, coordinator: Coordinator) {
        guard onSwipe != nil || onCurl != nil else { return }
        let pan = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleSwipe(_:)))
        pan.delegate = coordinator
        // One finger: two are a pinch, and a pinch zooms.
        pan.maximumNumberOfTouches = 1
        scrollView.addGestureRecognizer(pan)
        coordinator.swipe = pan
        // The curl's drag owns a horizontal finger outright: the scroll view's own pan waits
        // for it to fail, so a fit-to-width page does not scroll under a turning sheet. A
        // vertical finger or a zoomed page fails the drag at once, and the scroll view pans.
        if onCurl != nil { scrollView.panGestureRecognizer.require(toFail: pan) }
    }
}

extension ScrollingPage.Coordinator {

    /// Turns the page when the finger lifts, by ``fadeSwipeStep(travel:threshold:)``, or
    /// hands every phase of the drag to the curl.
    @objc func handleSwipe(_ recogniser: UIPanGestureRecognizer) {
        guard let view = recogniser.view else { return }
        if let onCurl {
            let travel = Double(recogniser.translation(in: view).x)
            switch recogniser.state {
            case .began: onCurl.handle(.began(travel: travel))
            case .changed: onCurl.handle(.changed(travel: travel))
            case .ended:
                onCurl.handle(.ended(travel: travel, velocity: Double(recogniser.velocity(in: view).x)))
            case .cancelled, .failed: onCurl.handle(.ended(travel: travel, velocity: 0))
            default: break
            }
            return
        }
        guard recogniser.state == .ended else { return }
        let step = fadeSwipeStep(travel: recogniser.translation(in: view).x)
        if step != 0 { onSwipe?(step) }
    }

    /// Tells the curl where this page is drawn, so a turn starts on it rather than on the
    /// page fitted to the screen. Read when a turn starts, never per frame.
    func reportSheet(to curl: CurlDrag?) {
        onCurl = curl
        curl?.sheet = { [weak imageView] in
            imageView.map { $0.convert($0.bounds, to: nil) }
        }
    }

    /// The swipe starts only where ``pagePanTurns(contentWidth:boundsWidth:velocity:)``
    /// says so. Every other recogniser starts as before.
    func gestureRecognizerShouldBegin(_ recogniser: UIGestureRecognizer) -> Bool {
        guard recogniser === swipe, let pan = swipe, let scrollView = pan.view as? UIScrollView else {
            return true
        }
        let image = shownImage.map { CGSize(width: $0.width, height: $0.height) } ?? scrollView.bounds.size
        return pagePanTurns(
            pageWidth: pageWidth(image: image, bounds: scrollView.bounds.size, zoomScale: scrollView.zoomScale),
            boundsWidth: scrollView.bounds.width,
            velocity: pan.velocity(in: scrollView)
        )
    }

    /// With the scroll view's own pan, so a fit-to-width page still scrolls down while the
    /// finger also moves sideways in Fast fade. Never in Curl, where the turn owns the finger.
    func gestureRecognizer(
        _ recogniser: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        onCurl == nil && (recogniser === swipe || other === swipe)
    }
}
#endif
