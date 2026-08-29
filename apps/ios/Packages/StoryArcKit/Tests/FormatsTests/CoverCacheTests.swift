import CoreGraphics
import Foundation
import Testing

@testable import Formats

/// The cover cache: what it keeps apart, and what it forgets.
///
/// Android's `CoverCacheTest` asserts the same four things.
@Suite("Cover cache")
struct CoverCacheTests {

    private let directory = URL.temporaryDirectory
        .appending(path: "cover-cache-\(UUID().uuidString)", directoryHint: .isDirectory)

    private func cache() -> CoverCache { CoverCache(directory: directory) }

    /// A one-colour bitmap. The pixels are not the subject; the filing is.
    ///
    /// Throwing rather than force-unwrapping: a `CGContext` that cannot be made is a broken
    /// test host, and `#require` says so where a crash would only say the line number.
    private func image(width: Int = 8, height: Int = 8) throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    @Test("A stored cover reads back")
    func roundTrip() throws {
        let cache = cache()
        defer { cache.clear() }

        cache.store(try image(), for: "bone.cbz", maxPixelSize: 200)

        #expect(cache.image(for: "bone.cbz", maxPixelSize: 200) != nil)
    }

    /// The clause this exists for: "display resolution" is a property of the layout as well
    /// as the device, and the grid and the list ask for different sizes.
    @Test("A cover cached for one size is not served for another")
    func sizesAreSeparate() throws {
        let cache = cache()
        defer { cache.clear() }

        cache.store(try image(), for: "bone.cbz", maxPixelSize: 200)

        #expect(cache.image(for: "bone.cbz", maxPixelSize: 400) == nil)
    }

    /// A publication id can carry a path, and a path carries separators. A file name is not
    /// where that should be discovered.
    @Test("An identity that looks like a path is still one file")
    func pathLikeIdentityIsSafe() throws {
        let cache = cache()
        defer { cache.clear() }

        cache.store(try image(), for: "/Users/someone/Comics/../Bone #1.cbz", maxPixelSize: 200)

        #expect(cache.image(for: "/Users/someone/Comics/../Bone #1.cbz", maxPixelSize: 200) != nil)
    }

    @Test("Clearing forgets every cover")
    func clearing() throws {
        let cache = cache()
        cache.store(try image(), for: "a", maxPixelSize: 200)
        cache.store(try image(), for: "b", maxPixelSize: 200)

        cache.clear()

        #expect(cache.image(for: "a", maxPixelSize: 200) == nil)
        #expect(cache.image(for: "b", maxPixelSize: 200) == nil)
    }

    @Test("Asking for a cover nobody stored is not an error")
    func missingIsNil() {
        #expect(cache().image(for: "never-seen", maxPixelSize: 200) == nil)
    }
}
