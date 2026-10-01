import Testing

import StoryArcCore
@testable import ReaderFeature

/// `ebook-reader`, *Fixed-layout EPUB*: "background colour ... remain available, because it
/// applies to the container rather than the text" — D34 builds that into the live comic
/// reader rather than leaving it reachable only from Settings' own per-series default.
///
/// A mirror of `ReadingDefaultsChoosingTests`' matte cases: the rule is the same four lines
/// either side applies, so the tests are the same shape.
@Suite("The comic reader's own matte")
struct ReaderMatteTests {

    @Test("A matte swatch works over a comic default stored as Original")
    func theMatteWorksOverOriginal() {
        let updated = ReaderMatte.matting("#E8EFE6", over: ReadingTheme(preset: .original))

        #expect(
            updated.custom?.background == "#E8EFE6",
            """
            The matte did nothing over a theme stored as Original. Original refuses every \
            palette, and the comic reader reads only the matte.
            """
        )
    }

    @Test("No matte removes the colour and keeps the preset")
    func noMatteClearsTheColour() {
        let matted = ReaderMatte.matting("#E8EFE6", over: ReadingTheme(preset: .calm))

        let cleared = ReaderMatte.matting(nil, over: matted)

        #expect(cleared.preset == .calm)
        #expect(cleared.custom == nil, "The no-matte swatch left a colour in force.")
    }

    @Test("A matte over a plain preset keeps that preset")
    func theMatteKeepsAnOrdinaryPreset() {
        let updated = ReaderMatte.matting("#1B2430", over: ReadingTheme(preset: .quiet))

        #expect(updated.preset == .quiet, "choosing a matte changed the preset underneath it")
        #expect(updated.custom?.background == "#1B2430")
    }
}
