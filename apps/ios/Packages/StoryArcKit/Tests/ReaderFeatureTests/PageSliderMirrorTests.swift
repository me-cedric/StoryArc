import SwiftUI
import Testing

@testable import ReaderFeature

/// Spec line 44: the page slider is mirrored under right-to-left, so page one sits at the
/// right end. Android's `PageSliderMirrorTest` asserts the same rule.
@Suite("Page slider mirroring")
struct PageSliderMirrorTests {

    @Test("Left-to-right keeps the ordinary track direction")
    func leftToRight() {
        #expect(sliderLayoutDirection(isRightToLeft: false) == .leftToRight)
    }

    @Test("Right-to-left mirrors the track")
    func rightToLeft() {
        #expect(sliderLayoutDirection(isRightToLeft: true) == .rightToLeft)
    }
}
