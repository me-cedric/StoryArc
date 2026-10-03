import CoreGraphics
import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// Task 16.10: the player asks the library for a cover already decoded, from a synchronous
/// closure that cannot await the disk fetch ``LibraryModel/cover(for:maxPixelSize:)`` does.
/// ``LibraryModel/cachedCover(for:)`` is the half of that method this suite is for — the read
/// with no fetch behind it.
@Suite("Cached cover")
@MainActor
struct CachedCoverTests {

    private func onePixelImage() throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil,
                width: 2,
                height: 2,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(CGColor(red: 1, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        return try #require(context.makeImage())
    }

    @Test("A publication with no decoded cover yet gives nil, not a fetch")
    func noCoverYet() {
        let library = LibraryModel()
        let publication = Publication(
            identity: PublicationIdentity(normalizedPath: "/tmp/none-\(UUID().uuidString).m4b"),
            format: .m4b,
            displayTitle: "Fixture",
            origin: .inferred
        )

        #expect(library.cachedCover(for: publication) == nil)
    }

    @Test("A cover already decoded for this publication comes back as-is")
    func returnsWhatIsAlreadyCached() throws {
        let library = LibraryModel()
        let publication = Publication(
            identity: PublicationIdentity(normalizedPath: "/tmp/cached-\(UUID().uuidString).epub"),
            format: .epub,
            displayTitle: "Fixture",
            origin: .inferred
        )
        let image = try onePixelImage()
        library.covers[publication.id] = image

        let cached = try #require(library.cachedCover(for: publication))
        #expect(cached.width == image.width)
        #expect(cached.height == image.height)
    }
}
