import CoreGraphics
import Testing

@testable import ReaderFeature
@testable import StoryArcCore

/// That a spread curls as one sheet rather than losing a page.
///
/// `comic-reader`: a pair is shown side by side "AND a page detected as a single wide spread
/// is shown alone, never split across two turns". Curl was excluded from the pairing, so a
/// reader who chose it in landscape stopped seeing spreads at all — and the shader, handed the
/// leading page alone, turned half of one. D14 composites the slot into one texture instead.
///
/// Android's `SpreadTextureTest` asserts the same table.
@Suite("A spread curls as one surface")
struct SpreadTextureTests {

    private func page(width: Int, height: Int) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB), let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        return context.makeImage()
    }

    @Test("Curl is one of the modes that pair")
    func curlPairs() {
        // The one-line defect. Every mode that draws a slot as a picture pairs; only the
        // strip does not.
        #expect(PageTransition.pageCurl.pairsPages)
        #expect(PageTransition.slide.pairsPages)
        #expect(PageTransition.fastFade.pairsPages)
        #expect(!PageTransition.verticalScroll.pairsPages)
        #expect(!PageTransition.horizontalScroll.pairsPages)
    }

    @Test("Two pages make one texture twice as wide as either half")
    func twoPagesMakeOneTexture() throws {
        let left = try #require(page(width: 400, height: 600))
        let right = try #require(page(width: 400, height: 600))
        let texture = try #require(SpreadTexture.composite([left, right]))

        #expect(texture.width == 800)
        #expect(texture.height == 600)
        // The shader fits by ratio, so the shape is the whole of what it is handed: a spread
        // that came out one page wide would letterbox half the screen and turn one page.
        #expect(Double(texture.width) / Double(texture.height) == 800.0 / 600.0)
    }

    @Test("A slot of one page is handed straight through")
    func onePageCostsNothing() throws {
        let only = try #require(page(width: 400, height: 600))
        #expect(SpreadTexture.composite([only]) === only)
        #expect(SpreadTexture.composite([]) == nil)
    }

    @Test("The halves are equal, and the taller page sets the height")
    func theHalvesAreEqual() {
        // `ReaderContainers.half(at:)` gives each page an equal share and its tap arithmetic
        // depends on that. A composite that sized each half to its own page would move the
        // tap zones off the pages they belong to.
        let area = SpreadTexture.area(of: [CGSize(width: 400, height: 600), CGSize(width: 300, height: 900)])
        #expect(area.height == 900)
        // The first page at 900 high is 600 wide; the second is 300. The wider one sets it.
        #expect(area.half == 600)
        #expect(area.width == 1200)
    }

    @Test("A page narrower than its half is centred in it, not pushed against the fold")
    func aNarrowPageIsCentred() {
        let placed = SpreadTexture.placed(
            CGSize(width: 300, height: 900), inHalfAt: 600, half: 600, height: 900
        )
        #expect(placed.height == 900)
        #expect(placed.width == 300)
        #expect(placed.minX == 750)
        #expect(placed.minY == 0)
    }

    @Test("A page of no size places nothing rather than dividing by zero")
    func anEmptyPageIsRefused() {
        #expect(SpreadTexture.placed(CGSize(width: 0, height: 0), inHalfAt: 0, half: 10, height: 10) == .zero)
        #expect(SpreadTexture.placed(CGSize(width: 10, height: 10), inHalfAt: 0, half: 0, height: 0) == .zero)
    }
}
