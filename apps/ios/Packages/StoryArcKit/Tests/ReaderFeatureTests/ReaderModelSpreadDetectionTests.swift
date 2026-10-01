import CoreGraphics
import Foundation
import Testing

import StoryArcCore
@testable import ReaderFeature

/// That a decoded page's own shape is judged by `PageDecoder.isSpread`'s margin, not by a bare
/// `width > height` with no tolerance.
///
/// D27: `PageDecoder.isSpread` had no production caller on either platform — the inline rule
/// at the two `noteDecoded` sites ran instead, with no margin, so a page one percent wider
/// than tall from a slight scan skew counted as a spread. The decision keeps the 1.2 margin
/// "materially wider" implies and calls `isSpread` at both sites. Android's
/// `ReaderDecodingSpreadDetectionTest` asserts the same two cases.
@MainActor
@Suite("A decoded page's own shape is judged with a margin")
struct ReaderModelSpreadDetectionTests {
    /// A solid-colour image of the given pixel size, for a test that only cares about shape.
    private func image(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        guard let context, let made = context.makeImage() else {
            fatalError("could not make a \(width)x\(height) test image")
        }
        return made
    }

    private func model() -> ReaderModel {
        ReaderModel(
            publication: Publication(
                identity: PublicationIdentity(normalizedPath: "/spread-detection.cbz"),
                format: .cbz,
                displayTitle: "Spread detection",
                origin: .inferred
            ),
            url: URL(fileURLWithPath: "/spread-detection.cbz")
        )
    }

    @Test("A page a touch wider than tall, from scan skew, is not a spread")
    func aTouchWiderIsNotASpread() {
        let reader = model()
        // 1.05x: materially within a slight skew, nowhere near PageDecoder.isSpread's 1.2.
        reader.noteDecoded(image(width: 1050, height: 1000), at: 0)
        #expect(!reader.wideIndices.contains(0))
    }

    @Test("A page half again as wide as it is tall is a spread")
    func materiallyWiderIsASpread() {
        let reader = model()
        reader.noteDecoded(image(width: 1300, height: 1000), at: 0)
        #expect(reader.wideIndices.contains(0))
    }
}
