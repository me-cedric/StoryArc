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

    /// Task 1.3's fourth case, and the record of where it actually lives.
    ///
    /// **This used to say a cover that could not be decoded "reaches this as no pixels at
    /// all", and it does not.** ``PublicationDetailView/derivedWash()`` guards on
    /// `let cover` before it calls ``StoryArcCore/CoverAccent/pixels(of:)``, so a cover that
    /// failed to decode never becomes an empty census — the page simply has no cover and
    /// ``DetailWash/drawn(_:isPlain:)`` returns zero, which ``nothingToDraw`` is the
    /// assertion for. Android's page is in the same position for the same reason:
    /// `rememberDetailAccent` is handed `null` and never asks the extractor, and
    /// `CoverAccent.pixels`' own zero-size guard is unreachable because `Bitmap` refuses a
    /// zero dimension at construction.
    ///
    /// So the empty census is the *defensive* shape rather than the reachable one, and it is
    /// still worth pinning: it is what keeps a cover with no colour and a cover with no
    /// pixels from becoming two different states on the page. Android asserts the same
    /// answer from the same shape in `DetailAccentTest.aCoverThatNeverDecodedYieldsNothing`.
    @Test("An undecodable cover yields no wash")
    func noPixelsYieldNothing() {
        #expect(DetailWash.of(cover: [], canvas: darkCanvas, text: darkText) == nil)
        #expect(DetailWash.of(cover: [], canvas: lightCanvas, text: lightText) == nil)
    }

    /// The adjustment case again, from the other end of the scale.
    ///
    /// A pale cover on the light palette is the symmetric failure to a near-black cover on
    /// the dark one, and it was untested: every "must be adjusted" assertion in this file
    /// walked the same direction. ``StoryArcCore/CoverAccent/legible(_:on:)`` tries darker
    /// and lighter at each step, so the two directions are separate code paths and a change
    /// that broke one would leave the other green.
    @Test("A pale colour on the light palette is adjusted too")
    func aPaleColourIsAdjusted() throws {
        let wash = try #require(
            DetailWash.of(cover: field(0xF2D9_8C), canvas: lightCanvas, text: lightText)
        )

        #expect(wash.tint != "#F2D98C")
        #expect(ReadingContrast.ratio(wash.tint, lightCanvas) >= CoverAccent.floor)
        let washed = DetailWash.blend(wash.tint, into: lightCanvas, by: wash.strength)
        #expect(ReadingContrast.ratio(washed, lightText) >= ReadingContrast.aa)
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
// MARK: What the page draws

    /// The three answers, and the reason there are three.
    ///
    /// A page is composed before its cover is decoded, so every publication renders once
    /// with no wash and then again with one. Expressing that as a \`Double\` is what lets the
    /// view interpolate the change instead of cutting to it — an \`if let\` around the
    /// gradient has nothing to animate between, which is why the arrival used to flash.
    @Test("A cover with no colour to give draws nothing")
    func nothingToDraw() {
        #expect(DetailWash.drawn(nil, isPlain: false) == 0)
    }

    /// **Replaced, not softened.** A reader who asked for more contrast did not ask for a
    /// paler version of less, and a softened wash is how a screen lands marginally below the
    /// floor rather than clearly above it.
    @Test("Increased contrast or reduced transparency removes the wash rather than dimming it")
    func plainDrawsNothing() {
        let wash = DetailWash(tint: "#DC143C", strength: DetailWash.strongest)
        #expect(DetailWash.drawn(wash, isPlain: true) == 0)
    }

    @Test("Otherwise the page draws exactly the strength the wash asked for")
    func drawsItsStrength() {
        let wash = DetailWash(tint: "#DC143C", strength: 0.18)
        #expect(DetailWash.drawn(wash, isPlain: false) == 0.18)
    }

    /// The property the crossfade rests on: arriving at a cover moves one number, so there
    /// is something to interpolate. If these two were ever equal the fade would be invisible
    /// and the hard cut would be back without any test going red.
    @Test("A cover arriving is a change in one value, which is what makes it animatable")
    func arrivalIsInterpolable() {
        let wash = DetailWash(tint: "#2E5AAC", strength: 0.18)
        #expect(DetailWash.drawn(nil, isPlain: false) != DetailWash.drawn(wash, isPlain: false))
    }
}
