import SwiftUI
import Testing

@testable import DesignSystem

/// When Natural's grain is drawn, and when it is refused.
///
/// Every refusal in `settings-and-about` and `design.md` is a line here. Android's
/// `PaperGrainTest` asserts the same table, plus the API floor `RuntimeShader` imposes
/// there and nothing imposes here, and minus Reduce Transparency, which Android has no
/// setting for.
@Suite("Paper grain")
struct PaperGrainTests {
    @Test("Grain is drawn with Natural on and both accessibility settings off")
    func drawnByDefault() {
        #expect(PaperGrain.isDrawn(natural: true, reduceTransparency: false, contrast: .standard))
    }

    @Test("Grain belongs to Natural and to nothing else")
    func onlyUnderNatural() {
        // `design.md`: the accents reach the whole app, "actual paper grain appears only
        // where text is read" — and only when the theme that owns it is on.
        #expect(!PaperGrain.isDrawn(natural: false, reduceTransparency: false, contrast: .standard))
    }

    @Test("Reduce Transparency turns it off")
    func reduceTransparencyRefusesIt() {
        // Named by the requirement, and the reason is not a preference: grain is a
        // per-pixel modulation of the page, so it eats contrast from every letterform
        // drawn on it.
        #expect(!PaperGrain.isDrawn(natural: true, reduceTransparency: true, contrast: .standard))
    }

    @Test("Increase Contrast turns it off, from the other direction")
    func increaseContrastRefusesIt() {
        // A reader who asked for more contrast is not asking for a texture that removes
        // some.
        #expect(!PaperGrain.isDrawn(natural: true, reduceTransparency: false, contrast: .increased))
    }

    @Test("A cell is one physical size, whatever the panel's scale")
    func cellIsMeasuredInDevicePixels() {
        // A cell measured in points would be three physical pixels across on a Pro and two
        // on an SE, which is two different papers.
        #expect(PaperGrain.cell(atDisplayScale: 3) * 3 == PaperGrain.cellPixels)
        #expect(PaperGrain.cell(atDisplayScale: 2) * 2 == PaperGrain.cellPixels)
        // A scale below 1 is not a display, and dividing by it would magnify the grain
        // rather than leaving it alone.
        #expect(PaperGrain.cell(atDisplayScale: 0) == PaperGrain.cellPixels)
    }

    @Test("The tuning numbers are the same three Android uses")
    func tuningIsMirrored() {
        // Not a tautology: these are the whole of what a screen has to judge, and the two
        // platforms drifting apart on them is the one way this becomes two textures. If a
        // screenshot moves one, it moves in both files or this says so.
        #expect(PaperGrain.intensity == 0.045)
        #expect(PaperGrain.cellPixels == 1.5)
        #expect(PaperGrain.fineOctave == 0.35)
    }
}
