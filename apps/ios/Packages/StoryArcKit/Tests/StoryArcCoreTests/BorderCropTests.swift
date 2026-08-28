import Testing

@testable import StoryArcCore

@Suite("Border crop")
struct BorderCropTests {
    /// A page with `margin` pixels of `paper` around a block of `art`.
    private func page(
        width: Int = 100,
        height: Int = 100,
        margin: Int,
        paper: Int = 255,
        art: Int = 40
    ) -> BorderCrop.Sample {
        { x, y in
            let inside = x >= margin && y >= margin
                && x < width - margin && y < height - margin
            return inside ? art : paper
        }
    }

    @Test("A white margin is found on every edge")
    func findsWhiteMargin() {
        let inset = BorderCrop.inset(width: 100, height: 100, sample: page(margin: 10))
        #expect(inset == BorderCrop.Inset(top: 10, left: 10, bottom: 10, right: 10))
    }

    @Test("A black margin is found too")
    func findsBlackMargin() {
        // `comic-reader` says "white or black". A scan of a dark page on a dark platen has
        // the same problem and the same remedy.
        let sample = page(margin: 6, paper: 0, art: 200)
        #expect(BorderCrop.inset(width: 100, height: 100, sample: sample).top == 6)
    }

    @Test("A page with no margin is left alone")
    func leavesArtworkAlone() {
        let inset = BorderCrop.inset(width: 100, height: 100) { _, _ in 128 }
        #expect(inset.isEmpty)
    }

    @Test("A mid-grey band is not a margin")
    func greyIsNotAMargin() {
        // Flat grey is as likely to be artwork as border, and cropping into a page is worse
        // than leaving its border on.
        let inset = BorderCrop.inset(width: 100, height: 100, sample: page(margin: 10, paper: 128))
        #expect(inset.isEmpty)
    }

    @Test("A gradient is not a margin")
    func gradientIsNotAMargin() {
        // The fixture pages are gradients, and every row of one is uniform along its own
        // length. Without an edge to end at, a gradient would read as a deep margin and the
        // top of the artwork would be quietly cut off.
        let inset = BorderCrop.inset(width: 100, height: 100) { _, y in 255 - y * 2 }
        #expect(inset.isEmpty)
    }

    @Test("A page that is all one colour is left alone")
    func blankPage() {
        // No edge means no margin. A page with nothing on it has nothing to trim to, and
        // handing back a sliver of blank is worse than handing back the blank.
        #expect(BorderCrop.inset(width: 100, height: 100) { _, _ in 255 }.isEmpty)
    }

    @Test("Nothing is trimmed past the limit")
    func refusesToTakeTooMuch() {
        // A page that reads as nine tenths margin is a page the sampler misread, and a
        // sliver of artwork is the one outcome worse than an untrimmed border.
        let inset = BorderCrop.inset(width: 100, height: 100, sample: page(margin: 45))
        #expect(inset.top + inset.bottom < 100, "something is always left")
        #expect(inset.top <= 40)
    }

    @Test("A page too small to sample is left alone")
    func tinyPage() {
        #expect(BorderCrop.inset(width: 1, height: 1) { _, _ in 255 }.isEmpty)
    }
}
