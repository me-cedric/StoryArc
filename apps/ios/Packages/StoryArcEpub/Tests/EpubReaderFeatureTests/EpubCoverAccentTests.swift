import CoreGraphics
import Foundation
import Testing

import StoryArcCore
@testable import EpubReaderFeature

/// The end of an EPUB takes the cover's accent, as the comic reader's end screen does. D21,
/// task 9.7. Android's `EpubCoverAccentTest` asserts the same three things.
@MainActor
@Suite("The EPUB end of book takes the cover accent")
struct EpubCoverAccentTests {

    private static let corpus: URL = {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            let candidate = dir.appending(path: "packages/test-fixtures")
            if FileManager.default.fileExists(atPath: candidate.appending(path: "manifest.json").path) {
                return candidate
            }
            dir = dir.deletingLastPathComponent()
        }
        fatalError("fixture corpus not found above \(#filePath)")
    }()

    private func opened(_ name: String) async -> EpubReaderModel {
        let url = Self.corpus.appending(path: "ebooks/\(name)")
        let reader = EpubReaderModel(
            publication: Publication(
                identity: PublicationIdentity(normalizedPath: url.path),
                format: .epub,
                displayTitle: name,
                origin: .embedded
            ),
            url: url
        )
        await reader.open()
        return reader
    }

    /// A 4 by 4 image of one colour.
    private func image(red: UInt8, green: UInt8, blue: UInt8) throws -> CGImage {
        var bytes = [UInt8](repeating: 255, count: 4 * 4 * 4)
        for pixel in 0..<16 {
            bytes[pixel * 4] = red
            bytes[pixel * 4 + 1] = green
            bytes[pixel * 4 + 2] = blue
        }
        let context = try #require(CGContext(
            data: &bytes, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        return try #require(context.makeImage())
    }

    @Test("A book with a coloured cover gives its end of book that cover's accent")
    func aColouredCoverGivesItsAccent() async throws {
        // `fixture.epub` declares a cover image, a solid #255B97 blue.
        let reader = await opened("fixture.epub")

        let colours = try #require(reader.coverColours)
        #expect(colours.accent != colours.wash)
    }

    @Test("The label on the accent clears the 3:1 floor, and so does the accent on its wash")
    func theAccentIsLegible() async throws {
        let colours = try #require(await opened("fixture.epub").coverColours)

        #expect(ReadingContrast.ratio(colours.onAccent, colours.accent) >= 3)
        #expect(ReadingContrast.ratio(colours.accent, colours.wash) >= 3)
    }

    @Test("A grey cover, or no cover, keeps the brand accent")
    func aGreyCoverKeepsTheBrandAccent() async throws {
        #expect(EpubReaderModel.coverColours(of: try image(red: 128, green: 128, blue: 128)) == nil)
        #expect(EpubReaderModel.coverColours(of: try image(red: 37, green: 91, blue: 151)) != nil)
        // `series.epub` declares no cover at all.
        #expect(await opened("series.epub").coverColours == nil)
    }
}
