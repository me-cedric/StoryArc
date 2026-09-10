import Foundation
import Testing

@testable import ReaderFeature

/// Where a tap turns a page, and where it does not.
///
/// `page-transitions`: "each zone is a third of the screen's width, leaving the middle
/// third to the chrome", and with the setting off "a tap anywhere toggles the chrome, and
/// no tap turns a page".
///
/// The zone was a quarter, which left half the screen doing nothing but toggling the
/// chrome. The fraction is pinned here because Android holds the same number in
/// `EDGE_ZONE_FRACTION`, and a change to one that is not made to the other is a reader
/// meeting two different readers. Android's `ReaderTapZonesTest` is this file.
struct ReaderTapZonesTests {

    /// What `handleTap(at:in:)` decides, as the rule alone.
    private func zone(x: CGFloat, width: CGFloat = 1200, turns: Bool = true) -> String {
        let edge = width * ZoomablePage.edgeZoneFraction
        if turns, x < edge { return "back" }
        if turns, x > width - edge { return "forward" }
        return "chrome"
    }

    @Test("Each zone is a third of the width")
    func third() {
        // By the boundary it produces rather than by identity with a literal: the two
        // print the same and compare unequal in the last bit, and what a reader meets is
        // the boundary. A third of 1200 is 400, and of 2400 is 800.
        #expect(1200 * ZoomablePage.edgeZoneFraction == 400)
        #expect(2400 * ZoomablePage.edgeZoneFraction == 800)
    }

    @Test("The leading third turns back and the trailing third turns forward")
    func edges() {
        #expect(zone(x: 360) == "back")
        #expect(zone(x: 840) == "forward")
    }

    @Test("The middle third is the chrome")
    func middle() {
        #expect(zone(x: 600) == "chrome")
        #expect(zone(x: 401) == "chrome")
        #expect(zone(x: 799) == "chrome")
    }

    @Test("The boundaries belong to the middle, so neither turn zone is a point wider")
    func boundaries() {
        #expect(zone(x: 400) == "chrome")
        #expect(zone(x: 800) == "chrome")
    }

    @Test("With the zones off every tap is the chrome")
    func off() {
        #expect(zone(x: 360, turns: false) == "chrome")
        #expect(zone(x: 600, turns: false) == "chrome")
        #expect(zone(x: 840, turns: false) == "chrome")
    }

    @Test("A wider screen keeps the same three shares")
    func wider() {
        #expect(zone(x: 600, width: 2400) == "back")
        #expect(zone(x: 1200, width: 2400) == "chrome")
        #expect(zone(x: 1800, width: 2400) == "forward")
    }
}
