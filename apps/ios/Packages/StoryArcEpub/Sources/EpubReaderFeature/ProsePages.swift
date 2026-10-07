internal import UIKit
internal import WebKit

// Where Readium keeps the pages a prose curl needs, read through UIKit.
//
// Task 4.3b of `reader-theming-and-page-transitions`, owner answer O14. A turn inside one
// resource is one `window.scrollBy` in the same web view, and the navigator answers in under
// one frame in most turns. A turn across a resource boundary goes through
// `PaginationView.slideToView`, which sleeps 100 ms when it is not animated. Measured on a
// simulator on 2026-10-07 by `ProseCurlOnABookTests`: 2 to 34 ms inside a chapter, 108 to 112
// ms across one, which is seven frames at 60 Hz. So the curl cannot wait for the navigator at
// a chapter end.
//
// It does not have to. Readium preloads the neighbouring resources, the next ones at their
// start and the previous ones at their end (`PaginationView.setCurrentIndex`), and lays each
// one out beside the current one in its paging scroll view. The page a boundary turn arrives
// at is already drawn there. So the curl rasters it before the navigator moves, which is
// route 1, "raster ahead", and costs no navigator round trip and no position write.
//
// ponytail: this reads Readium's view structure, not its API, the way `PaginatedScroll`
// does. When a Readium upgrade moves it, ``ahead(in:forward:isRightToLeft:)`` answers nil and
// the curl waits for the navigator, which is a stall at a chapter end and never a wrong page.
enum ProsePages {

    /// Whether a turn leaves the resource on screen.
    ///
    /// Readium's own guard in `EPUBReflowableSpreadView.go(to:options:)`, restated: the turn
    /// rounds the web view's offset to the next whole page in the turn's screen direction, and
    /// a target outside the content is the next resource.
    ///
    /// - Parameters:
    ///   - offset: the web view's horizontal content offset.
    ///   - width: the web view's width, which is one page.
    ///   - contentWidth: the width of all the resource's pages together.
    ///   - step: +1 for a turn to the page on the right, -1 for the page on the left.
    static func crossesResource(offset: CGFloat, width: CGFloat, contentWidth: CGFloat, step: CGFloat) -> Bool {
        guard width > 0 else { return true }
        let move = width * step
        let target = ((offset + move) / move).rounded() * move
        return !(0..<contentWidth ~= target)
    }

    /// Which screen direction a turn moves in: a forward turn shows the page on the right in a
    /// left-to-right book, and the page on the left in a right-to-left one.
    static func step(forward: Bool, isRightToLeft: Bool) -> CGFloat {
        forward != isRightToLeft ? 1 : -1
    }

    /// The page a turn arrives at, rastered before the navigator moves, or nil where the turn
    /// stays inside the resource or Readium holds no neighbour.
    ///
    /// - Parameter page: the navigator's own view.
    static func ahead(in page: UIView, forward: Bool, isRightToLeft: Bool) -> CGImage? {
        guard let paging = PaginatedScroll.find(in: page) else { return nil }
        let step = step(forward: forward, isRightToLeft: isRightToLeft)
        let width = paging.bounds.width
        guard let current = spread(in: paging, at: paging.contentOffset.x),
              let web = webScroll(in: current),
              crossesResource(
                  offset: web.contentOffset.x,
                  width: web.bounds.width,
                  contentWidth: web.contentSize.width,
                  step: step
              ),
              let neighbour = spread(in: paging, at: paging.contentOffset.x + width * step)
        else { return nil }
        return neighbour.raster(afterScreenUpdates: false)
    }

    /// The resource view Readium has laid out at `x` in its paging scroll view.
    static func spread(in paging: UIScrollView, at x: CGFloat) -> UIView? {
        paging.subviews.first { abs($0.frame.minX - x) < 1 && $0.frame.width > 0 }
    }

    /// The scroll view of the web view inside a resource view.
    static func webScroll(in view: UIView) -> UIScrollView? {
        if let web = view as? WKWebView { return web.scrollView }
        for subview in view.subviews {
            if let found = webScroll(in: subview) { return found }
        }
        return nil
    }
}
