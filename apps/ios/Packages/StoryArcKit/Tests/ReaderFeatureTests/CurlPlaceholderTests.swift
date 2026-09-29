import CoreGraphics
import SwiftUI
import Testing

@testable import ReaderFeature

/// The sheet a curl turns to while that page has not decoded (task 8.4).
///
/// `page-transitions` "The next page is not ready": the turn "runs against a placeholder
/// holding the correct aspect ratio".
@Suite("A curl turns to a placeholder while the next page decodes")
struct CurlPlaceholderTests {

    private let decoded = [2: "page two"]

    private func sheet(at display: Int?) -> String? {
        CurlPlaceholder.sheet(at: display, decoded: { decoded[$0] }, placeholder: { "placeholder for \($0)" })
    }

    @Test("A decoded neighbour is the page itself")
    func decodedNeighbour() {
        #expect(sheet(at: 2) == "page two")
    }

    @Test("A neighbour still decoding is the placeholder, not the outgoing page")
    func undecodedNeighbour() {
        #expect(sheet(at: 3) == "placeholder for 3")
    }

    @Test("Past either end there is no sheet, so nothing turns")
    func pastTheEnd() {
        #expect(sheet(at: nil) == nil)
    }

    @Test("The placeholder holds the page's own proportions")
    func proportions() {
        for (ratio, width, height) in [(2.0 / 3.0, 64, 96), (2.0, 128, 64), (0.0, 64, 96)] {
            let size = CurlPlaceholder.size(ratio: ratio)
            #expect(size.width == width && size.height == height, "ratio \(ratio)")
        }
    }

    @Test("The placeholder is the matte colour, edge to edge")
    func matteColour() throws {
        let image = try #require(CurlPlaceholder.image(ratio: 0.5, matte: Color(red: 1, green: 0, blue: 0)))
        #expect(image.width == 64 && image.height == 128)
        let data = try #require(image.dataProvider?.data)
        let bytes = try #require(CFDataGetBytePtr(data))
        let last = (image.height - 1) * image.bytesPerRow + (image.width - 1) * 4
        for offset in [0, last] {
            #expect(bytes[offset] == 255 && bytes[offset + 1] == 0 && bytes[offset + 2] == 0)
            #expect(bytes[offset + 3] == 255)
        }
    }
}
