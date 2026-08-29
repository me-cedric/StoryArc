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
                onTap: onTap
            )
        }
        #else
        // The package builds for macOS so the pure-Swift targets can be tested on
        // the host. Zoom is a touch feature; there is no Mac reader yet (ADR-0004).
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

        context.coordinator.imageView = imageView
        context.coordinator.zoomedScale = zoomedScale
        context.coordinator.onTap = onTap

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        // Two single-tap recognisers, and the split is deliberate.
        //
        // Requiring a single tap to wait for the double tap to fail delays *every*
        // tap by the double-tap interval. On the centre that costs nothing a reader
        // notices; on an edge it means a page turn arriving a third of a second
        // after the finger lifts, which feels broken — and `comic-reader` treats
        // the edge tap as a turn, not as a menu. An edge tap also cannot be the
        // first half of a zoom, so it has nothing to wait for.
        let edgeTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleSingleTap(_:))
        )
        edgeTap.delegate = context.coordinator
        scrollView.addGestureRecognizer(edgeTap)
        context.coordinator.edgeTap = edgeTap

        let centreTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleSingleTap(_:))
        )
        centreTap.require(toFail: doubleTap)
        centreTap.delegate = context.coordinator
        scrollView.addGestureRecognizer(centreTap)
        context.coordinator.centreTap = centreTap

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.onTap = onTap

        if context.coordinator.pageID != pageID {
            context.coordinator.pageID = pageID
            context.coordinator.imageView?.image = UIImage(cgImage: image)
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
        /// The fit SwiftUI last asked for, which is not always one that could be applied.
        var owed: OwedFit?
        /// Which fit the zoom was actually set from.
        var applied = AppliedFit()
        var imageView: UIImageView?
        var pageID: String
        var zoomedScale: CGFloat = 2.5
        var onTap: (CGPoint, CGSize) -> Void = { _, _ in }

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

/// A scroll view that says when it has been given a size.
///
/// `UIScrollViewDelegate` reports scrolling and zooming, never layout, and layout is
/// what a page opened before its first one is waiting for: a fit set against zero
/// bounds does nothing, and no scroll and no zoom follows to prompt another try.
///
/// Only a change of size is reported. Applying a fit sets the content size and the
/// insets, which lays the view out again — a report on every pass would be a loop.
private final class PageScrollView: UIScrollView {
    var onLayout: ((UIScrollView) -> Void)?
    private var lastSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastSize else { return }
        lastSize = bounds.size
        onLayout?(self)
    }
}
#endif
