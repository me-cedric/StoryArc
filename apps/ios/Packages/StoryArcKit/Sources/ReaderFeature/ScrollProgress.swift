internal import SwiftUI

internal import StoryArcCore

/// Where a continuous scroll sits within its current page, and the anchor that
/// returns to it.
///
/// `comic-reader` requires the scroll position "preserved exactly" across a reopen,
/// which a page *index* alone cannot do for a webtoon: a page many screens tall stops
/// scrolling anywhere along it, not just at its top. A struct of its own, beside
/// `ReaderModel`, so `ScrollProgressTests` can drive it with a plain `CGRect` — the
/// same reason `EarlyPageTallness` is split out.
enum ScrollProgress {
    /// How far a scroll has moved through a page, in the terms
    /// `ScrollViewProxy.scrollTo(_:anchor:)` takes back.
    ///
    /// Not the plain distance over the page's length. An anchor of `a` aligns the point
    /// `a` of the way down the page with the point `a` of the way down the viewport, so
    /// the viewport's leading edge lands `a × (page − viewport)` into the page. A plain
    /// distance restored that way came back short by up to a screen. So this is the
    /// distance over `page − viewport`: 0 with the page's leading edge at the viewport's,
    /// 1 with its trailing edge at the viewport's.
    ///
    /// The frame is in a coordinate space named at the `ScrollView` itself, so its
    /// origin is the page's distance from the viewport's leading edge: negative once the
    /// page has scrolled past it. A page no longer than the viewport has no room to be
    /// part-way through, and reads as 0.
    static func fraction(pageFrame: CGRect, viewport: CGSize, axis: ScrollAxis) -> Double {
        let origin = axis == .vertical ? pageFrame.minY : pageFrame.minX
        let length = axis == .vertical ? pageFrame.height : pageFrame.width
        let room = length - (axis == .vertical ? viewport.height : viewport.width)
        guard room > 0 else { return 0 }
        return min(1, max(0, Double(-origin / room)))
    }

    /// Where `ScrollViewProxy.scrollTo(_:anchor:)` should aim, to reopen at a stored
    /// fraction through a page.
    static func anchor(forFraction fraction: Double, axis: ScrollAxis) -> UnitPoint {
        let clamped = min(1, max(0, fraction))
        return axis == .vertical ? UnitPoint(x: 0.5, y: clamped) : UnitPoint(x: clamped, y: 0.5)
    }
}
