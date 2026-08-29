import CoreGraphics
import Testing

@testable import StoryArcCore

/// The cover-derived accent, case for case with Android's `CoverAccentTest`.
///
/// The pair exists for the reason the `PageOrdering` pair does: the two platforms
/// have to give one book one colour, and only two suites asserting the same cases
/// can say so.
@Suite("Cover colour census")
struct CoverAccentDominantTests {
    /// A block of one colour, as the sampler would hand it over.
    private func block(_ pixel: UInt32, count: Int = 1024) -> [UInt32] {
        Array(repeating: pixel, count: count)
    }

    @Test("A cover of one colour is that colour")
    func oneColour() {
        #expect(CoverAccent.dominant(of: block(0xDC14_3C)) == "#DC143C")
    }

    @Test("A greyscale cover has no accent at all")
    func greyscaleHasNone() {
        // A manga cover: ink, paper, and the greys between them. Deriving an accent
        // from these would tint every black-and-white book the same muddy nothing.
        let ramp = (0..<1024).map { step -> UInt32 in
            let level = UInt32(step % 256)
            return level << 16 | level << 8 | level
        }

        #expect(CoverAccent.dominant(of: ramp) == nil)
    }

    @Test("Nothing to count is no accent, not a crash")
    func emptyHasNone() {
        #expect(CoverAccent.dominant(of: []) == nil)
    }

    @Test("A mostly white cover still yields the colour it does carry")
    func colourUnderPaper() {
        // Three quarters paper, one quarter sky. The paper abstains, so the sky wins
        // — which is the whole point of ignoring near-white.
        let pixels = block(0xFF_FFFF, count: 768) + block(0x2E_5AAC, count: 256)

        #expect(CoverAccent.dominant(of: pixels) == "#2E5AAC")
    }

    @Test("A colour on a tenth of the cover is a logo, not an accent")
    func tooLittleColour() {
        let pixels = block(0xFF_FFFF, count: 1000) + block(0x2E_5AAC, count: 24)

        #expect(CoverAccent.dominant(of: pixels) == nil)
    }

    @Test("Alpha in the high bits is ignored rather than counted")
    func alphaIgnored() {
        #expect(CoverAccent.dominant(of: block(0xFFDC_143C)) == "#DC143C")
    }
}

@Suite("Cover accent legibility")
struct CoverAccentContrastTests {
    @Test("A dark accent on a dark wash is lightened until it clears the floor")
    func liftsOffDark() throws {
        let adjusted = try #require(CoverAccent.legible("#101820", on: "#0A0A0A"))

        #expect(ReadingContrast.ratio(adjusted, "#0A0A0A") >= CoverAccent.floor)
        #expect(adjusted != "#101820")
    }

    @Test("A colour that already clears the floor is left alone")
    func leavesLegibleAlone() {
        #expect(CoverAccent.legible("#FFFFFF", on: "#000000") == "#FFFFFF")
    }

    @Test("A floor no lightness can reach is refused rather than approximated")
    func refusesTheImpossible() {
        // Mid-grey has no colour at all that reaches 7:1 against it — white tops out
        // near 4, black near 5.3. Returning the nearest miss would be an accent that
        // fails the gate the whole exercise exists to pass.
        #expect(CoverAccent.legible("#4488CC", on: "#7F7F7F", ratio: ReadingContrast.aaa) == nil)
    }

    @Test("A cover with no colour derives nothing, so the caller keeps the brand accent")
    func greyDerivesNothing() {
        let grey = Array(repeating: UInt32(0x80_8080), count: 1024)

        #expect(CoverAccent.derived(from: grey) == nil)
    }

    @Test("What comes out of the accent path always clears the floor")
    func neverReturnsIllegible() throws {
        // The dark navy a night-sky cover yields, on the wash such a cover produces.
        // Raw, the accent would sit on itself at a ratio of 1:1 — the case the
        // adjustment exists for.
        let navy = Array(repeating: UInt32(0x0F_1B3A), count: 1024)
        let derived = try #require(CoverAccent.derived(from: navy))

        #expect(ReadingContrast.ratio(derived.accent, derived.wash) >= CoverAccent.floor)
        #expect(ReadingContrast.ratio(derived.wash, "#FFFFFF") >= ReadingContrast.aa)
        // And what is written on the accent is legible on it, which is the third pairing
        // this screen has and the one an eye is worst at judging.
        #expect(ReadingContrast.ratio(derived.onAccent, derived.accent) >= ReadingContrast.aa)
        #expect(derived.accent != "#0F1B3A")
    }

    @Test("The wash is dark enough for the white text that sits on it")
    func washCarriesWhiteText() throws {
        let pale = Array(repeating: UInt32(0xF2_D98C), count: 1024)
        let wash = try #require(CoverAccent.wash(from: pale))

        #expect(ReadingContrast.ratio(wash, "#FFFFFF") >= ReadingContrast.aa)
    }

    @Test("A cover with no colour has no wash either")
    func greyHasNoWash() {
        #expect(CoverAccent.wash(from: Array(repeating: UInt32(0x80_8080), count: 1024)) == nil)
    }
}

@Suite("Cover sampling")
struct CoverAccentSamplingTests {
    @Test("A drawn image comes back as the census grid")
    func samplesToTheGrid() throws {
        let image = try #require(solid(red: 0xDC, green: 0x14, blue: 0x3C))
        let pixels = try #require(CoverAccent.pixels(of: image))

        #expect(pixels.count == CoverAccent.sampleEdge * CoverAccent.sampleEdge)
        #expect(CoverAccent.dominant(of: pixels) == "#DC143C")
    }

    /// A 64×64 image of one colour, built the way a decoder would hand one over.
    private func solid(red: UInt8, green: UInt8, blue: UInt8) -> CGImage? {
        let edge = 64
        var bytes = [UInt8](repeating: 0, count: edge * edge * 4)
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            bytes[offset] = red
            bytes[offset + 1] = green
            bytes[offset + 2] = blue
            bytes[offset + 3] = 0xFF
        }
        return bytes.withUnsafeMutableBytes { buffer -> CGImage? in
            guard let base = buffer.baseAddress else { return nil }
            let context = CGContext(
                data: base,
                width: edge,
                height: edge,
                bitsPerComponent: 8,
                bytesPerRow: edge * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
            return context?.makeImage()
        }
    }
}
