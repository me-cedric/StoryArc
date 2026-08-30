import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// The cover-derived wash, and the floor it is never allowed to cross.
///
/// `pnpm tokens:check` holds the shipped palette to a WCAG floor and fails the build on a
/// pair below it. A colour pulled out of artwork at run time is the one colour that gate
/// cannot see, so the check has to be in the code and asserted here — the four cases the
/// tasks name, plus the invariant that produced them: **whatever comes back, body text over
/// it clears 4.5:1.**
@Suite("Cover wash")
struct DetailWashTests {

    /// A field of one colour, the way a cover arrives from `CoverAccent.pixels(of:)`.
    private func field(_ colour: UInt32, count: Int = 1024) -> [UInt32] {
        Array(repeating: colour, count: count)
    }

    /// The dark palette, as the page resolves it.
    private let darkCanvas = "#0F0D0B"
    private let darkText = "#F1EEEA"
    /// The light palette.
    private let lightCanvas = "#F8F6F4"
    private let lightText = "#181512"

    @Test("A strong cover colour gives a wash, and text over it clears the floor")
    func strongColourGivesALegibleWash() throws {
        let wash = try #require(
            DetailWash.of(cover: field(0xDC14_3C), canvas: darkCanvas, text: darkText)
        )

        #expect(wash.strength <= DetailWash.strongest)
        #expect(wash.strength >= DetailWash.faintest)
        let washed = DetailWash.blend(wash.tint, into: darkCanvas, by: wash.strength)
        #expect(ReadingContrast.ratio(washed, darkText) >= ReadingContrast.aa)
    }

    /// The adjustment case. A near-black cover has no contrast against a near-black canvas,
    /// so `CoverAccent.legible` has to move it before anything is drawn — and what it moved
    /// it to still has to leave the page readable.
    @Test("A colour that cannot be used raw is adjusted until it clears the floor")
    func aDarkColourIsAdjusted() throws {
        let wash = try #require(
            DetailWash.of(cover: field(0x1018_38), canvas: darkCanvas, text: darkText)
        )

        #expect(wash.tint != "#101838")
        #expect(ReadingContrast.ratio(wash.tint, darkCanvas) >= CoverAccent.floor)
        let washed = DetailWash.blend(wash.tint, into: darkCanvas, by: wash.strength)
        #expect(ReadingContrast.ratio(washed, darkText) >= ReadingContrast.aa)
    }

    /// The commonest case on a manga shelf, and the reason `nil` is a real answer: a
    /// black-and-white cover has no colour to lend, and inventing one from its greys would
    /// tint every such book the same muddy sepia.
    @Test("A monochrome cover yields no wash at all")
    func monochromeYieldsNothing() {
        #expect(DetailWash.of(cover: field(0x8080_80), canvas: darkCanvas, text: darkText) == nil)
        #expect(DetailWash.of(cover: field(0xFFFF_FF), canvas: lightCanvas, text: lightText) == nil)
    }

    /// A cover that could not be decoded reaches this as no pixels at all. It reads the same
    /// way as a cover with no colour, which is what keeps the page from having a third state.
    @Test("An undecodable cover yields no wash")
    func noPixelsYieldNothing() {
        #expect(DetailWash.of(cover: [], canvas: darkCanvas, text: darkText) == nil)
    }

    /// Both palettes, because the wash is checked against the page it is drawn on and the
    /// two pages are different colours. A wash computed once for dark and reused in light is
    /// the defect this keying exists to prevent.
    @Test(
        "Whatever comes back keeps body text above the floor, in both palettes",
        arguments: [0xDC14_3C, 0x2E5A_AC, 0xE8C4_1A, 0x1F7A_3D, 0x7B2F_8F] as [UInt32]
    )
    func everyAnswerIsLegible(colour: UInt32) {
        for (canvas, text) in [(darkCanvas, darkText), (lightCanvas, lightText)] {
            guard let wash = DetailWash.of(cover: field(colour), canvas: canvas, text: text) else {
                continue
            }
            let washed = DetailWash.blend(wash.tint, into: canvas, by: wash.strength)
            #expect(
                ReadingContrast.ratio(washed, text) >= ReadingContrast.aa,
                "\(String(colour, radix: 16)) on \(canvas) washed to \(washed)"
            )
        }
    }

    @Test("The blend is a plain composite, so nothing of the tint survives at zero")
    func blendEndpoints() {
        #expect(DetailWash.blend("#FF0000", into: "#000000", by: 0) == "#000000")
        #expect(DetailWash.blend("#FF0000", into: "#000000", by: 1) == "#FF0000")
        #expect(DetailWash.blend("#FFFFFF", into: "#000000", by: 0.5) == "#808080")
    }
}
