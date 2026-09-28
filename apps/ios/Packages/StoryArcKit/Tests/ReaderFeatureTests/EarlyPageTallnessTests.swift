import Testing

@testable import ReaderFeature

/// A webtoon that opens on a short title image is still recognised as tall.
///
/// `comic-reader` recognises a webtoon by pages "materially taller than they are wide".
/// Deciding from the first decoded page alone read a one-page title card as ordinary
/// panels and defaulted Scroll to horizontal for the whole chapter. Android's
/// `EarlyPageTallnessTest` asserts the same table.
@Suite("Early page tallness")
struct EarlyPageTallnessTests {

    @Test("A short first page does not decide it alone")
    func firstPageAloneIsNotEnough() {
        var tallness = EarlyPageTallness()
        tallness.note(ratio: 1.2, at: 0)
        #expect(tallness.tallestRatio == 1.2)

        tallness.note(ratio: 3.5, at: 1)
        #expect(tallness.tallestRatio == 3.5, "A taller page among the early ones should win.")
    }

    @Test("The tallest of the early pages is kept, whichever order they decode in")
    func tallestOfTheSampleWins() {
        var tallness = EarlyPageTallness()
        tallness.note(ratio: 3.5, at: 2)
        tallness.note(ratio: 1.2, at: 0)
        tallness.note(ratio: 2.0, at: 1)
        #expect(tallness.tallestRatio == 3.5)
    }

    @Test("A page past the sample does not raise the ratio")
    func pastTheSampleDoesNotCount() {
        var tallness = EarlyPageTallness()
        tallness.note(ratio: 1.0, at: 0)
        tallness.note(ratio: 9.0, at: EarlyPageTallness.sampleCount)
        #expect(
            tallness.tallestRatio == 1.0,
            """
            A page beyond the sample changed the ratio. The whole point of sampling only \
            the early pages is to answer without decoding the rest of the publication.
            """
        )
    }

    @Test("Nothing decoded yet reads as not tall")
    func nothingDecodedYet() {
        #expect(EarlyPageTallness().tallestRatio == 0)
    }
}
