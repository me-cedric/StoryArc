#if os(iOS)
internal import UIKit

// The press-and-drag that selects PDF text over a zoomed page. Split out of
// `ZoomablePage.swift`, which had reached the 400-line cap this project enforces —
// selection is the one gesture there with nothing to do with fit or zoom.
extension ScrollingPage {

    /// The press that starts a selection, installed only where there is text under the finger.
    ///
    /// `ebook-reader` requires a text-dependent control to be absent rather than present and
    /// inert, and a recogniser is a control: one that could never resolve would still swallow
    /// a long press the page has other plans for.
    func addSelection(to scrollView: UIScrollView, coordinator: Coordinator) {
        guard onSelect != nil else { return }
        let press = UILongPressGestureRecognizer(
            target: coordinator,
            action: #selector(Coordinator.handleSelection(_:))
        )
        // Long enough not to fire on a tap that is on its way to being a double tap, short
        // enough that a reader who means to select does not wonder whether it worked.
        press.minimumPressDuration = 0.35
        scrollView.addGestureRecognizer(press)
    }
}

extension ScrollingPage.Coordinator {

    /// A press that becomes a drag: the selection starts at the word pressed and runs to
    /// wherever the finger is now.
    ///
    /// The scroll is turned off for the length of it. Without that a zoomed page pans
    /// under the drag, and the reader selects one word while the page slides away.
    @objc func handleSelection(_ recogniser: UILongPressGestureRecognizer) {
        guard let imageView, let onSelect else { return }
        let point = normalisedPoint(
            recogniser.location(in: imageView),
            imageSize: imageView.image?.size ?? .zero,
            in: imageView.bounds.size
        )

        switch recogniser.state {
        case .began:
            (recogniser.view as? UIScrollView)?.isScrollEnabled = false
            selectionOrigin = point
            // The platform's own selection feedback, which is what a reader's thumb
            // already expects from a press that selects.
            UISelectionFeedbackGenerator().selectionChanged()
            onSelect(point, point, false)
        case .changed:
            guard let origin = selectionOrigin else { return }
            onSelect(origin, point, false)
        case .ended, .cancelled, .failed:
            (recogniser.view as? UIScrollView)?.isScrollEnabled = true
            guard let origin = selectionOrigin else { return }
            selectionOrigin = nil
            onSelect(origin, point, true)
        default:
            break
        }
    }
}
#endif
