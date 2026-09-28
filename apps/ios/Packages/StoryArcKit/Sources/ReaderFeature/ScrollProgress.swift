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
    /// How far into a page's own frame the viewport's leading edge sits, from that
    /// frame in the scroll's coordinate space.
    ///
    /// The frame's origin is the page's distance from the viewport's own leading
    /// edge, which is 0 in a coordinate space named at the `ScrollView` itself — so a
    /// page scrolled halfway past report a negative origin of minus half its length,
    /// and this turns that back into a plain 0…1 fraction.
    static func fraction(pageFrame: CGRect, axis: ScrollAxis) -> Double {
        let origin = axis == .vertical ? pageFrame.minY : pageFrame.minX
        let length = axis == .vertical ? pageFrame.height : pageFrame.width
        guard length > 0 else { return 0 }
        return min(1, max(0, Double(-origin / length)))
    }

    /// Where `ScrollViewProxy.scrollTo(_:anchor:)` should aim, to reopen at a stored
    /// fraction through a page.
    static func anchor(forFraction fraction: Double, axis: ScrollAxis) -> UnitPoint {
        let clamped = min(1, max(0, fraction))
        return axis == .vertical ? UnitPoint(x: 0.5, y: clamped) : UnitPoint(x: clamped, y: 0.5)
    }
}
