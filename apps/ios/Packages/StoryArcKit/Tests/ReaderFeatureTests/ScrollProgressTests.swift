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

    @Test("A page at the viewport's own edge reads as the very start of it")
    func atTheTopIsZero() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 1000)
        #expect(ScrollProgress.fraction(pageFrame: frame, axis: .vertical) == 0)
    }

    @Test("Scrolled halfway through a page reads as one half")
    func halfwayIsOneHalf() {
        let frame = CGRect(x: 0, y: -500, width: 100, height: 1000)
        #expect(ScrollProgress.fraction(pageFrame: frame, axis: .vertical) == 0.5)
    }

    @Test("A page not yet reached, further down the strip, reads as its own start")
    func notYetReachedIsZero() {
        let frame = CGRect(x: 0, y: 800, width: 100, height: 1000)
        #expect(ScrollProgress.fraction(pageFrame: frame, axis: .vertical) == 0)
    }

    @Test("A page scrolled past reads as fully through, not past 1")
    func scrolledPastClampsToOne() {
        let frame = CGRect(x: 0, y: -1500, width: 100, height: 1000)
        #expect(ScrollProgress.fraction(pageFrame: frame, axis: .vertical) == 1)
    }

    @Test("A page with no length along the axis is never divided by zero")
    func zeroLengthIsZero() {
        let frame = CGRect(x: 0, y: -50, width: 100, height: 0)
        #expect(ScrollProgress.fraction(pageFrame: frame, axis: .vertical) == 0)
    }

    @Test("Horizontal Scroll reads its own axis, not the vertical one")
    func horizontalReadsX() {
        let frame = CGRect(x: -250, y: -9_999, width: 1000, height: 100)
        #expect(ScrollProgress.fraction(pageFrame: frame, axis: .horizontal) == 0.25)
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
