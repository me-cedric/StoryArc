import SwiftUI
import Testing

@testable import DesignSystem

/// The one hex parser, which replaced four: the reader's, the settings', the detail
/// background's and the EPUB theme sheet's. These pin the outputs the four agreed on, so the
/// swatch, the matte and the cover wash cannot drift apart again.
@Suite("Hex colour")
struct HexColourTests {
    @Test("Six digits, with or without the hash, are the opaque sRGB colour")
    func sixDigits() {
        let expected = Color(.sRGB, red: 236 / 255, green: 124 / 255, blue: 39 / 255, opacity: 1)
        #expect(Color(hex: "#EC7C27") == expected)
        #expect(Color(hex: "ec7c27") == expected)
        #expect(Color(hex: "#000000") == Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1))
    }

    @Test("CSS shorthand doubles each digit")
    func shorthand() {
        #expect(Color(hex: "#abc") == Color(hex: "#aabbcc"))
    }

    @Test("Anything else is nil, so the caller's fallback draws")
    func rejects() {
        #expect(Color(hex: "") == nil)
        #expect(Color(hex: "#GGGGGG") == nil)
        #expect(Color(hex: "#FFFF") == nil)
        #expect(Color(hex: "#FFFFFFFF") == nil)
    }
}
