public import SwiftUI

public import StoryArcCore

#if os(iOS)
internal import UIKit
#endif

/// One page, fitted and zoomable.
///
/// `comic-reader`: "the page zooms about the pinch centre, pans within bounds, and
/// double-tap toggles between fit and a zoomed level centred on the tapped point".
///
/// A `UIScrollView` rather than a SwiftUI gesture stack. Pinch about a centre,
/// bounded panning, rubber-banding at the edges and deceleration are all things it
/// already does correctly, and — the reason that matters here — a scroll view at
/// minimum zoom does not consume horizontal drags, so the pager above it still
/// gets the swipe. A hand-rolled `MagnifyGesture` has to fight the pager for every
/// one of those, which is the same fight the right-to-left work lost twice.
///
/// Taps are handled here too, for the same reason: a SwiftUI tap layered over a
/// scroll view is a second recogniser competing with the first.
struct ZoomablePage: View {
    /// A quarter of the width each side: hittable on a phone, and the centre still
    /// has room. Shared with the reader, which decides what an edge tap means.
    static let edgeZoneFraction: CGFloat = 0.25

    let image: CGImage
    /// Changes when the page does, so the zoom resets rather than carrying a
    /// magnified corner of the last page onto the next one.
    let pageID: String
    /// How the page is sized before any pinch. `comic-reader` names four modes.
    let fit: PageFit
    /// Where the tap landed, in the page's own coordinates, and how big the page
    /// was — the caller decides whether that is an edge or the centre.
    let onTap: (CGPoint, CGSize) -> Void
    /// How far the page is magnified, reported when a pinch or a double-tap settles.
    ///
    /// `publication-formats` asks for a page to be "re-decoded at higher resolution when
    /// the user zooms", and the scroll view is the only thing that knows how far. Sent
    /// on the *end* of a zoom rather than on every frame: a pinch produces dozens of
    /// changes a second, and a full-page decode per frame would be the opposite of
    /// making the page feel sharp.
    let onZoom: (Double) -> Void

    /// The marks and the live selection to paint over the page, normalised to it.
    ///
    /// Empty for a comic and for a PDF with no text layer, which is what makes the whole
    /// selection apparatus cost a scanned publication nothing.
    var decoration: PdfPageDecoration = .none

    /// A press and drag over the text, reported in normalised page coordinates, with `true`
    /// once the finger has lifted.
    ///
    /// `nil` where there is no text to select, which is also what stops the recogniser being
    /// installed at all — a gesture that could only ever fail is a gesture that eats presses.
    var onSelect: ((CGPoint, CGPoint, Bool) -> Void)?

    var body: some View {
        #if os(iOS)
        // The size the fit is computed from comes from SwiftUI rather than from the
        // scroll view's bounds: `updateUIView` runs before the first layout, so
        // `bounds` is still zero on the way in. The scroll view's own bounds are
        // consulted for one thing only — whether there has been a layout at all —
        // because a fit cannot be applied to a view that has not had one.
        GeometryReader { geometry in
            ScrollingPage(
                image: image,
                pageID: pageID,
                fit: fit,
                viewport: geometry.size,
                onTap: onTap,
                onZoom: onZoom,
                decoration: decoration,
                onSelect: onSelect
            )
        }
        #else
        // The package builds for macOS so the pure-Swift targets can be tested on
        // the host. Zoom is a touch feature; there is no Mac reader yet (ADR-0004).
        // No pinch to report on the host build, so `onZoom` is never called there.
        Image(decorative: image, scale: 1)
            .resizable()
            .scaledToFit()
        #endif
    }
}

#if os(iOS)
private struct ScrollingPage: UIViewRepresentable {
    let image: CGImage
    let pageID: String
    let fit: PageFit
    let viewport: CGSize
    let onTap: (CGPoint, CGSize) -> Void
    let onZoom: (Double) -> Void
    let decoration: PdfPageDecoration
    let onSelect: ((CGPoint, CGPoint, Bool) -> Void)?

    /// How far a double-tap zooms in. Enough to read the lettering on a dense
    /// page, not so far that the reader loses the panel they tapped.
    private let zoomedScale: CGFloat = 2.5

    func makeUIView(context: Context) -> UIScrollView {
        let imageView = UIImageView(image: UIImage(cgImage: image))
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true

        let scrollView = PageScrollView()
        scrollView.delegate = context.coordinator
        // The one thing a `UIScrollViewDelegate` cannot tell the coordinator is when
        // the view was laid out, and that is exactly when a page which arrived before
        // its layout becomes fittable. See ``PageScrollView``.
        scrollView.onLayout = { [weak coordinator = context.coordinator] view in
            coordinator?.applyFit(to: view)
        }
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 6
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .black
        // The pager owns the horizontal swipe, and it only gets it if this view
        // stops bouncing horizontally at minimum zoom.
        scrollView.bounces = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.addSubview(imageView)

        let overlay = PdfPageOverlayView(frame: imageView.bounds)
        overlay.imageSize = CGSize(width: image.width, height: image.height)
        imageView.addSubview(overlay)

        context.coordinator.imageView = imageView
        context.coordinator.shownImage = image
        context.coordinator.overlay = overlay
        context.coordinator.zoomedScale = zoomedScale
        context.coordinator.onTap = onTap
        context.coordinator.onZoom = onZoom

        addSelection(to: scrollView, coordinator: context.coordinator)
        addTaps(to: scrollView, coordinator: context.coordinator)

        return scrollView
    }

    /// The press that starts a selection, installed only where there is text under the finger.
    ///
    /// `ebook-reader` requires a text-dependent control to be absent rather than present and
    /// inert, and a recogniser is a control: one that could never resolve would still swallow
    /// a long press the page has other plans for.
    private func addSelection(to scrollView: UIScrollView, coordinator: Coordinator) {
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

    /// The three tap recognisers, and the split between the last two is deliberate.
    ///
    /// Requiring a single tap to wait for the double tap to fail delays *every* tap by the
    /// double-tap interval. On the centre that costs nothing a reader notices; on an edge it
    /// means a page turn arriving a third of a second after the finger lifts, which feels
    /// broken — and `comic-reader` treats the edge tap as a turn, not as a menu. An edge tap
    /// also cannot be the first half of a zoom, so it has nothing to wait for.
    private func addTaps(to scrollView: UIScrollView, coordinator: Coordinator) {
        let doubleTap = UITapGestureRecognizer(
            target: coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        let edgeTap = UITapGestureRecognizer(
            target: coordinator,
            action: #selector(Coordinator.handleSingleTap(_:))
        )
        edgeTap.delegate = coordinator
        scrollView.addGestureRecognizer(edgeTap)
        coordinator.edgeTap = edgeTap

        let centreTap = UITapGestureRecognizer(
            target: coordinator,
            action: #selector(Coordinator.handleSingleTap(_:))
        )
        centreTap.require(toFail: doubleTap)
        centreTap.delegate = coordinator
        scrollView.addGestureRecognizer(centreTap)
        coordinator.centreTap = centreTap
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onZoom = onZoom
        context.coordinator.onSelect = onSelect
        context.coordinator.overlay?.decoration = decoration

        if context.coordinator.pageID != pageID {
            context.coordinator.pageID = pageID
            context.coordinator.shownImage = image
            context.coordinator.imageView?.image = UIImage(cgImage: image)
        } else if context.coordinator.shownImage !== image {
            // The same page at a different resolution — the copy re-decoded for a held
            // zoom, or the display one coming back when the zoom ends. Swapped without
            // touching `pageID`, because that is what resets the zoom, and a reader who
            // held a pinch to see the lettering did not ask to be zoomed back out.
            //
            // The aspect ratio is unchanged, so the fit, the offset and the insets all
            // still describe the same page and nothing has to be recomputed.
            context.coordinator.shownImage = image
            context.coordinator.imageView?.image = UIImage(cgImage: image)
            context.coordinator.overlay?.imageSize =
                CGSize(width: image.width, height: image.height)
        }
        context.coordinator.layout(scrollView)

        // What the page is owed. The fit is applied when the page, the mode or the
        // size changes, and at no other time — otherwise every redraw would undo the
        // reader's pinch. Whether *now* is the time is ``Coordinator/applyFit(to:)``'s
        // to decide, because on the way in there is not yet a laid-out view to fit to.
        context.coordinator.owed = OwedFit(
            pageID: pageID,
            mode: fit,
            imageSize: CGSize(width: image.width, height: image.height),
            viewport: viewport
        )
        context.coordinator.applyFit(to: scrollView)
    }

    func makeCoordinator() -> Coordinator { Coordinator(pageID: pageID) }

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        weak var edgeTap: UITapGestureRecognizer?
        weak var centreTap: UITapGestureRecognizer?
        weak var overlay: PdfPageOverlayView?
        var onSelect: ((CGPoint, CGPoint, Bool) -> Void)?
        /// Where the press started, normalised to the page. The drag extends from it.
        private var selectionOrigin: CGPoint?
        /// The fit SwiftUI last asked for, which is not always one that could be applied.
        var owed: OwedFit?
        /// Which fit the zoom was actually set from.
        var applied = AppliedFit()
        var imageView: UIImageView?
        /// Which decode is on screen, so a re-decode at a different resolution is
        /// recognised as the same page rather than as a turn.
        var shownImage: CGImage?
        var pageID: String
        var zoomedScale: CGFloat = 2.5
        var onTap: (CGPoint, CGSize) -> Void = { _, _ in }
        var onZoom: (Double) -> Void = { _ in }

        init(pageID: String) {
            self.pageID = pageID
        }

        /// Opens the page at the fit it is owed, if there is now a view that can hold one.
        ///
        /// Called both from `updateUIView` and from the scroll view's own layout, because
        /// on a cold launch the two happen in that order: SwiftUI asks for the fit while
        /// the scroll view is still zero-sized, and the layout that makes it possible
        /// arrives afterwards with nothing to prompt another update.
        func applyFit(to scrollView: UIScrollView) {
            guard let owed, applied.claim(owed.key, layout: scrollView.bounds.size) else { return }

            scrollView.setZoomScale(owed.scale(upTo: scrollView.maximumZoomScale), animated: false)
            layout(scrollView)
            if owed.opensAtTheTop {
                scrollView.contentOffset = CGPoint(x: 0, y: -scrollView.contentInset.top)
            }
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) { layout(scrollView) }

        /// The end of a pinch, and of an animated double-tap zoom.
        ///
        /// The only place the scale is reported from. `scrollViewDidZoom` fires on every
        /// frame of the gesture, and re-decoding a page there would decode it sixty
        /// times on the way to the magnification the reader actually wanted.
        func scrollViewDidEndZooming(
            _ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat
        ) {
            onZoom(Double(scale))
        }

        /// Keeps the page centred while it is smaller than the screen.
        ///
        /// Without this a zoomed-out page sits in the top-left corner, which looks
        /// like a layout bug rather than a fit.
        func layout(_ scrollView: UIScrollView) {
            guard let imageView, scrollView.bounds.width > 0 else { return }
            let scaled = CGSize(
                width: scrollView.bounds.width * scrollView.zoomScale,
                height: scrollView.bounds.height * scrollView.zoomScale
            )
            imageView.frame = CGRect(origin: .zero, size: scaled)
            scrollView.contentSize = scaled

            // The overlay is the whole content, so the normalised rectangles it draws land
            // on the same words at every zoom.
            overlay?.frame = imageView.bounds

            let horizontal = max(0, (scrollView.bounds.width - scaled.width) / 2)
            let vertical = max(0, (scrollView.bounds.height - scaled.height) / 2)
            scrollView.contentInset = UIEdgeInsets(
                top: vertical, left: horizontal, bottom: vertical, right: horizontal
            )
        }

        /// Sends each single tap to the recogniser that should own it.
        func gestureRecognizer(
            _ recogniser: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            guard let view = recogniser.view else { return true }
            let x = touch.location(in: view).x
            let edge = view.bounds.width * ZoomablePage.edgeZoneFraction
            let isEdge = x < edge || x > view.bounds.width - edge
            if recogniser === edgeTap { return isEdge }
            if recogniser === centreTap { return !isEdge }
            return true
        }

        @objc func handleSingleTap(_ recogniser: UITapGestureRecognizer) {
            guard let view = recogniser.view else { return }
            onTap(recogniser.location(in: view), view.bounds.size)
        }

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

        @objc func handleDoubleTap(_ recogniser: UITapGestureRecognizer) {
            guard let scrollView = recogniser.view as? UIScrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
                return
            }
            // Centred on what was tapped, not on the middle of the screen: the
            // point of a double-tap is to magnify *that* panel.
            let point = recogniser.location(in: imageView)
            let size = CGSize(
                width: scrollView.bounds.width / zoomedScale,
                height: scrollView.bounds.height / zoomedScale
            )
            scrollView.zoom(
                to: CGRect(
                    x: point.x - size.width / 2,
                    y: point.y - size.height / 2,
                    width: size.width,
                    height: size.height
                ),
                animated: true
            )
        }
    }
}
#endif
