import Foundation
import Testing

@testable import LibraryFeature
import Persistence
import StoryArcCore

/// A chapter opened from the Kavita browser starts where the server says the reader is.
///
/// The field report: Continue, a chapter row and a reading-list entry all opened at page one,
/// and closing the chapter then reported page one back, moving the server behind. Android's
/// `KavitaOpenSeedTest` asserts the same cases.
@Suite("The first open of a Kavita chapter is seeded from the server")
struct KavitaOpenSeedTests {

    private func book(_ format: PublicationFormat) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/Kavita/\(UUID().uuidString).\(format)"),
            format: format,
            displayTitle: "Chapter",
            origin: .inferred
        )
    }

    @Test("A comic is seeded at the server's page, stamped as synchronised")
    func aComicIsSeededAtThePage() async throws {
        let progress = try ProgressStore.inMemory()
        let comic = book(.cbz)

        await seedKavitaOpen(comic, pagesRead: 4, of: 10, into: progress)

        let found = try #require(try await progress.progress(for: comic.identity))
        #expect(found.position == .page(index: 3, of: 10))
        #expect(found.syncedPosition == found.position, "the server already holds this position")
    }

    @Test("An EPUB is seeded as a fraction its reader opens at, not as a page")
    func anEpubIsSeededAsAFraction() async throws {
        let progress = try ProgressStore.inMemory()
        let epub = book(.epub)

        await seedKavitaOpen(epub, pagesRead: 6, of: 11, into: progress)

        let found = try #require(try await progress.progress(for: epub.identity))
        guard case let .reflowable(progression, locator, _) = found.position else {
            Issue.record("an EPUB seeded as \(found.position), which its reader cannot open")
            return
        }
        #expect(progression == ReadingPosition.page(index: 5, of: 11).fraction)
        #expect(locator.isEmpty)
    }

    @Test("A chapter this device already holds a position for is left alone")
    func anExistingRecordIsKept() async throws {
        let progress = try ProgressStore.inMemory()
        let comic = book(.cbz)
        try await progress.save(
            ReadingProgress(identity: comic.identity, position: .page(index: 8, of: 10), updatedAt: .now)
        )

        await seedKavitaOpen(comic, pagesRead: 2, of: 10, into: progress)

        #expect(try await progress.progress(for: comic.identity)?.position == .page(index: 8, of: 10))
    }
}
