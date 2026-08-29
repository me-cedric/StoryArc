import Foundation
import Testing

@testable import Persistence
@testable import StoryArcCore

/// What an interrupted scan wrote down, and what a resumed one reads back.
///
/// `local-library` requires a folder scan to be "cancellable and resumable". A scan of ten
/// thousand comics is minutes of opening archives, and a reader whose phone reclaimed the
/// process would otherwise watch the whole thing happen again from an empty grid.
@Suite("Scan journal")
struct ScanJournalTests {
    private func journal() throws -> ScanJournal {
        let defaults = try #require(UserDefaults(suiteName: "app.storyarc.tests.\(UUID())"))
        return ScanJournal(defaults: defaults)
    }

    private func publication(_ name: String, series: String? = nil) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/comics/\(name).cbz"),
            format: .cbz,
            displayTitle: name,
            series: series,
            number: "1",
            authors: ["Jeff Smith"],
            origin: .embedded,
            pageCount: 24,
            coverPath: "001.png",
            readingDirection: .rightToLeft,
            streaming: .downloadOnly
        )
    }

    @Test("A folder nothing has scanned has nothing to resume")
    func emptyJournal() throws {
        let journal = try journal()
        defer { journal.reset() }
        #expect(journal.indexed(inFolder: "/comics").isEmpty)
    }

    @Test("What a scan recorded comes back whole")
    func roundTrip() throws {
        // Whole, because the resumed scan puts these straight into the library rather than
        // re-reading them: anything lost here is a row that is wrong until the next scan.
        let journal = try journal()
        defer { journal.reset() }
        journal.record([publication("Bone", series: "Bone")], inFolder: "/comics")

        let read = try #require(journal.indexed(inFolder: "/comics").first)
        #expect(read.displayTitle == "Bone")
        #expect(read.series == "Bone")
        #expect(read.number == "1")
        #expect(read.authors == ["Jeff Smith"])
        #expect(read.pageCount == 24)
        #expect(read.coverPath == "001.png")
        #expect(read.readingDirection == .rightToLeft)
        #expect(read.streaming == .downloadOnly)
        #expect(read.identity.normalizedPath == "/comics/Bone.cbz")
    }

    @Test("Two folders keep their own journals")
    func perFolder() throws {
        // A reader with two libraries can interrupt a scan of one of them, and the other
        // must not come back holding its files.
        let journal = try journal()
        defer { journal.reset() }
        journal.record([publication("Bone")], inFolder: "/comics")
        journal.record([publication("Maus"), publication("Persepolis")], inFolder: "/books")

        #expect(journal.indexed(inFolder: "/comics").count == 1)
        #expect(journal.indexed(inFolder: "/books").count == 2)
    }

    @Test("A finished scan leaves nothing to resume")
    func clearing() throws {
        // Cleared rather than kept. This is a journal, not the metadata cache `sources`
        // asks for, and a journal that outlived its scan would be a stale library nobody
        // decided to keep.
        let journal = try journal()
        defer { journal.reset() }
        journal.record([publication("Bone")], inFolder: "/comics")
        journal.clear(folder: "/comics")
        #expect(journal.indexed(inFolder: "/comics").isEmpty)
    }

    @Test("Clearing one folder leaves the others alone")
    func clearingIsNarrow() throws {
        let journal = try journal()
        defer { journal.reset() }
        journal.record([publication("Bone")], inFolder: "/comics")
        journal.record([publication("Maus")], inFolder: "/books")
        journal.clear(folder: "/comics")
        #expect(journal.indexed(inFolder: "/books").count == 1)
    }

    @Test("A later record replaces the earlier one rather than adding to it")
    func recordReplaces() throws {
        // The writer holds the whole list anyway, and a store that could be half-written is
        // exactly the thing a resume must not read.
        let journal = try journal()
        defer { journal.reset() }
        journal.record([publication("Bone")], inFolder: "/comics")
        journal.record([publication("Bone"), publication("Maus")], inFolder: "/comics")
        #expect(journal.indexed(inFolder: "/comics").map(\.displayTitle) == ["Bone", "Maus"])
    }
}
