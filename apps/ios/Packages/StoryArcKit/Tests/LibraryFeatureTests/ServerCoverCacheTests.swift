import CoreGraphics
import Foundation
import ImageIO
import StoryArcCore
import Testing
import UniformTypeIdentifiers

@testable import LibraryFeature

/// Task 22.2's own correction: a server shelf's card is drawn "through the authenticated
/// client and the cover cache", and neither ``ServerShelfCover`` nor
/// ``HomeServerShelfCover`` used one — every appearance of either card asked the server
/// again and decoded the answer again. ``LibraryModel/serverCover(for:maxPixelSize:fetch:)``
/// is the one door both now go through, so this is asserted once here rather than by
/// re-fetching an emulator's Kavita mock from two different screens.
///
/// Every id below carries a fresh `UUID`: `serverCover` writes to the same shared disk
/// cache ``LibraryModel/cover(for:maxPixelSize:)`` already does, with no test seam to point
/// it elsewhere — the same limitation that method has always had. A unique id keeps this
/// suite's writes from colliding with another suite's, or with a real cover on a
/// developer's machine; it does not clean them up, because a stray file in a *cache*
/// directory is, by definition, harmless. Android's `ServerCoverCacheTest` asserts the same
/// three cases against its own disk cache.
@Suite("Server cover cache")
@MainActor
struct ServerCoverCacheTests {

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

    private func onePixelPNG() throws -> Data {
        let image = try onePixelImage()
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test("A cover fetched once is not asked of the server a second time")
    func fetchedOnce() async throws {
        let id = "srv:server-a:series:\(UUID().uuidString)"
        let library = LibraryModel()
        var fetches = 0

        let first = await library.serverCover(for: id, maxPixelSize: 180) {
            fetches += 1
            return try onePixelPNG()
        }
        #expect(first != nil)
        #expect(fetches == 1)

        // A fresh `LibraryModel` -- a different card composed after the first one left the
        // hierarchy, or the app relaunched -- reads the same disk directory `serverCover`
        // always names, which is the property this cache is for.
        let second = await LibraryModel().serverCover(for: id, maxPixelSize: 180) {
            fetches += 1
            return try onePixelPNG()
        }

        #expect(fetches == 1, "a cover already on disk was fetched from the server again")
        #expect(second != nil)
    }

    @Test("Two servers answering the same small integer do not share a cache entry")
    func scopedByServer() async throws {
        let shared = UUID().uuidString
        let library = LibraryModel()
        var serverAFetches = 0
        var serverBFetches = 0

        _ = await library.serverCover(for: "srv:server-a:series:\(shared)", maxPixelSize: 180) {
            serverAFetches += 1
            return try onePixelPNG()
        }
        _ = await library.serverCover(for: "srv:server-b:series:\(shared)", maxPixelSize: 180) {
            serverBFetches += 1
            return try onePixelPNG()
        }

        #expect(
            serverBFetches == 1,
            "server B's own request for the same series id was answered from server A's cache entry"
        )
        #expect(serverAFetches == 1)
    }

    @Test("A reading list's locked cover is never drawn for a collection with the same number")
    func lockedCoverScopedByKind() async throws {
        let server = UUID().uuidString
        let list = RememberedShelf(kind: .readingList, sourceID: UUID(), serverID: 3, title: "Weekly")
        let collection = RememberedShelf(
            kind: .collection, sourceID: list.sourceID, serverID: 3, title: "Staff picks"
        )
        let library = LibraryModel()

        _ = await library.serverCover(
            for: HomeServerShelfCover.lockedCoverID(server: server, shelf: list),
            maxPixelSize: 360
        ) { try onePixelPNG() }
        var collectionFetched = false
        _ = await library.serverCover(
            for: HomeServerShelfCover.lockedCoverID(server: server, shelf: collection),
            maxPixelSize: 360
        ) {
            collectionFetched = true
            return try onePixelPNG()
        }

        #expect(collectionFetched, "the collection's card drew the reading list's cached cover")
    }

    @Test("A fetch that fails caches nothing, so the next appearance tries again")
    func failedFetchIsNotCached() async throws {
        let id = "srv:server-a:series:\(UUID().uuidString)"
        let library = LibraryModel()

        let failed = await library.serverCover(for: id, maxPixelSize: 180) {
            struct Refused: Error {}
            throw Refused()
        }
        #expect(failed == nil)

        var secondAttemptRan = false
        _ = await library.serverCover(for: id, maxPixelSize: 180) {
            secondAttemptRan = true
            return try onePixelPNG()
        }

        #expect(secondAttemptRan)
    }
}
