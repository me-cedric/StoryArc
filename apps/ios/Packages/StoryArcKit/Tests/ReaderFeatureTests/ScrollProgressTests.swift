import CoreGraphics
import SwiftUI
import Testing

import StoryArcCore
@testable import ReaderFeature

/// The fraction through a page a continuous scroll sits at, and the anchor that
/// restores it. Android's `ScrollProgressTest` asserts the same table, from a pixel
/// offset and size rather than a `CGRect` — the two platforms' own native shapes for
/// "where a page sits" — but the same fractions.
@Suite("Scroll progress")
struct ScrollProgressTests {

    private let viewport = CGSize(width: 100, height: 200)

    @Test("A page at the viewport's own edge reads as the very start of it")
    func atTheTopIsZero() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 1000)
        #expect(ScrollProgress.fraction(pageFrame: frame, viewport: viewport, axis: .vertical) == 0)
    }

    @Test("The fraction is in the anchor's own terms: through the page less one viewport")
    func fractionIsInAnchorTerms() {
        // 400 of the 800 points this page can scroll through. An anchor of 0.5 puts the
        // page's point 500 at the viewport's point 100, so the viewport's top lands 400
        // into the page — where it was. The plain 400 / 1000 = 0.4 landed at 320.
        let frame = CGRect(x: 0, y: -400, width: 100, height: 1000)
        let fraction = ScrollProgress.fraction(pageFrame: frame, viewport: viewport, axis: .vertical)
        #expect(fraction == 0.5)
        let anchor = ScrollProgress.anchor(forFraction: fraction, axis: .vertical)
        let pageTopInViewport = anchor.y * viewport.height - anchor.y * frame.height
        #expect(pageTopInViewport == frame.minY)
    }

    @Test("A page not yet reached, further down the strip, reads as its own start")
    func notYetReachedIsZero() {
        let frame = CGRect(x: 0, y: 800, width: 100, height: 1000)
        #expect(ScrollProgress.fraction(pageFrame: frame, viewport: viewport, axis: .vertical) == 0)
    }

    @Test("A page scrolled to its own end reads as 1, and past it is clamped to 1")
    func scrolledToTheEndIsOne() {
        let atEnd = CGRect(x: 0, y: -800, width: 100, height: 1000)
        #expect(ScrollProgress.fraction(pageFrame: atEnd, viewport: viewport, axis: .vertical) == 1)
        let past = CGRect(x: 0, y: -1500, width: 100, height: 1000)
        #expect(ScrollProgress.fraction(pageFrame: past, viewport: viewport, axis: .vertical) == 1)
    }

    @Test("A page no longer than the viewport has no part-way to be, and reads as 0")
    func shortPageIsZero() {
        let frame = CGRect(x: 0, y: -50, width: 100, height: 150)
        #expect(ScrollProgress.fraction(pageFrame: frame, viewport: viewport, axis: .vertical) == 0)
    }

    @Test("Horizontal Scroll reads its own axis, not the vertical one")
    func horizontalReadsX() {
        let wide = CGSize(width: 200, height: 100)
        let frame = CGRect(x: -200, y: -9_999, width: 1000, height: 100)
        #expect(ScrollProgress.fraction(pageFrame: frame, viewport: wide, axis: .horizontal) == 0.25)
    }

    @Test("The restore anchor carries the fraction into the axis SwiftUI scrolls along")
    func anchorFollowsTheAxis() {
        #expect(ScrollProgress.anchor(forFraction: 0.3, axis: .vertical) == UnitPoint(x: 0.5, y: 0.3))
        #expect(ScrollProgress.anchor(forFraction: 0.3, axis: .horizontal) == UnitPoint(x: 0.3, y: 0.5))
    }

    @Test("A stored fraction outside 0...1 is clamped before it becomes an anchor")
    func anchorClampsAStaleFraction() {
        #expect(ScrollProgress.anchor(forFraction: 4, axis: .vertical) == UnitPoint(x: 0.5, y: 1))
        #expect(ScrollProgress.anchor(forFraction: -1, axis: .vertical) == UnitPoint(x: 0.5, y: 0))
    }
}
