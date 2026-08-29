import Foundation
import Testing

@testable import Persistence
@testable import StoryArcCore

/// The library snapshot: what survives a round trip, and what a bad one costs.
///
/// Android's `LibraryCacheTest` asserts the same four things.
@Suite("Library cache")
struct LibraryCacheTests {

    private let directory = URL.temporaryDirectory
        .appending(path: "library-cache-\(UUID().uuidString)", directoryHint: .isDirectory)

    private func cache() -> LibraryCache { LibraryCache(directory: directory) }

    private func publication(_ title: String, source: UUID? = nil) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/comics/\(title).cbz"),
            format: .cbz,
            displayTitle: title,
            series: "Bone",
            number: "1",
            authors: ["Jeff Smith"],
            origin: .embedded,
            pageCount: 24,
            coverPath: "001.jpg",
            readingDirection: .rightToLeft,
            sourceID: source
        )
    }

    @Test("A snapshot reads back with its publications intact")
    func roundTrip() throws {
        let cache = cache()
        defer { cache.clear() }
        let source = UUID()
        let moment = Date(timeIntervalSince1970: 1_700_000_000)

        cache.write(
            LibraryCache.Snapshot(
                refreshedAt: moment,
                publications: [publication("Bone", source: source)],
                locations: ["x": "/comics/Bone.cbz"]
            )
        )
        let read = try #require(cache.read())

        #expect(read.refreshedAt == moment)
        #expect(read.locations == ["x": "/comics/Bone.cbz"])
        #expect(read.publications.count == 1)
        // The fields the grid draws from, and the one the library assigns rather than the
        // indexer — a cached publication attributed to nothing is a source with no items.
        let restored = try #require(read.publications.first)
        #expect(restored.displayTitle == "Bone")
        #expect(restored.series == "Bone")
        #expect(restored.pageCount == 24)
        #expect(restored.readingDirection == .rightToLeft)
        #expect(restored.sourceID == source)
    }

    @Test("No snapshot is not an error")
    func missingIsNil() {
        #expect(cache().read() == nil)
    }

    /// A snapshot this build cannot read costs a rescan, which is what a cache miss is for.
    /// It must never be a crash, and never a half-restored shelf.
    @Test("An unreadable snapshot reads as none at all")
    func corruptIsNil() throws {
        let cache = cache()
        defer { cache.clear() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: directory.appending(path: "library.json"))

        #expect(cache.read() == nil)
    }

    @Test("Clearing forgets the shelf")
    func clearing() {
        let cache = cache()
        cache.write(LibraryCache.Snapshot(refreshedAt: .now, publications: [publication("Bone")], locations: [:]))

        cache.clear()

        #expect(cache.read() == nil)
    }
}
