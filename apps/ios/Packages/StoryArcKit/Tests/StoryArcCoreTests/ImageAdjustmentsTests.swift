import Foundation
import Testing

@testable import StoryArcCore

@Suite("Image adjustments")
struct ImageAdjustmentsTests {
    @Test("A fresh adjustment does nothing")
    func neutralByDefault() {
        // Worth asserting rather than assuming: `isNeutral` is what stops a filter chain
        // being inserted under every page of every comic.
        #expect(ImageAdjustments().isNeutral)
        #expect(ImageAdjustments(brightness: 0.1).isNeutral == false)
        #expect(ImageAdjustments(isGreyscale: true).isNeutral == false)
    }

    @Test("Values outside the range are brought back into it")
    func clamps() {
        // A slider cannot produce these; a decoded value from an older or altered store
        // can, and a contrast of 40 is a black page.
        #expect(ImageAdjustments(brightness: 9).brightness == 1)
        #expect(ImageAdjustments(contrast: -9).contrast == -1)
        #expect(ImageAdjustments(sharpness: -1).sharpness == 0)
    }

    @Test("Contrast is offered as the multiplier a renderer takes")
    func contrastFactor() {
        #expect(ImageAdjustments().contrastFactor == 1)
        #expect(ImageAdjustments(contrast: 1).contrastFactor == 2)
        #expect(ImageAdjustments(contrast: -1).contrastFactor == 0)
    }

    @Test("A stored adjustment survives a round trip")
    func codable() throws {
        let original = ImageAdjustments(
            brightness: 0.25, contrast: -0.5, sharpness: 0.75, isInverted: true
        )
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(ImageAdjustments.self, from: data) == original)
    }

    @Test("A store written before a field existed still reads")
    func decodesWhatIsMissing() throws {
        // The same forgiveness `ShelfSettings` needs, for the same reason: a build that
        // adds a field must not lose what an earlier build wrote.
        let data = Data(#"{"brightness":0.5}"#.utf8)
        let decoded = try JSONDecoder().decode(ImageAdjustments.self, from: data)
        #expect(decoded.brightness == 0.5)
        #expect(decoded.isGreyscale == false)
    }
}
