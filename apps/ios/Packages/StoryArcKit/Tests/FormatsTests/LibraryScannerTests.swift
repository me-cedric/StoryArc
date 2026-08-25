import Foundation
import StoryArcCore
import Testing

@testable import Formats

/// The scan is asserted against the real corpus directory, which is exactly the
/// mixed folder a user would point at: several formats, a damaged file, a refused
/// one, and an EPUB among the comics.
@Suite("Library scanning")
struct LibraryScannerTests {
    private var corpus: URL { FixtureCorpus.root }

    /// A throwaway library laid out the way a real one is: a folder per series,
    /// numbered files inside it.
    private func shelf(series: String, files: [String]) throws -> URL {
        let root = URL.temporaryDirectory.appending(path: "shelf-\(UUID().uuidString)")
        let folder = root.appending(path: series)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (index, source) in files.enumerated() {
            try FileManager.default.copyItem(
                at: FixtureCorpus.url("comics/\(source)"),
                to: folder.appending(path: String(format: "%02d.cbz", index + 1))
            )
        }
        return root
    }

    @Test("A subfolder names the series when the filename does not")
    func folderIsASeries() async throws {
        // `local-library`: "each subfolder is presented as a series whose name is
        // the folder name". "Bone/01.cbz" says which issue it is and not which
        // series; the folder is the only thing that knows.
        let root = try shelf(series: "Bone", files: ["single-page.cbz", "natural-sort.cbz"])
        defer { try? FileManager.default.removeItem(at: root) }

        let publications = await LibraryScanner.scanAll(folderAt: root)

        #expect(publications.count == 2)
        #expect(publications.allSatisfy { $0.series == "Bone" })
        #expect(Set(publications.compactMap(\.number)) == ["1", "2"])
    }

    @Test("The library's own folder is not a series")
    func rootIsNotASeries() async throws {
        // Everything in the corpus root would otherwise be filed under
        // "test-fixtures", which is a path, not a story.
        let publications = await LibraryScanner.scanAll(folderAt: corpus)
        #expect(!publications.contains { $0.series == corpus.lastPathComponent })
    }

    private func events(in folder: URL) async -> [ScanEvent] {
        var collected: [ScanEvent] = []
        for await event in LibraryScanner.scan(folderAt: folder) { collected.append(event) }
        return collected
    }

    @Test("A folder of mixed formats yields a publication for each")
    func findsEverything() async throws {
        let publications = await LibraryScanner.scanAll(folderAt: corpus)
        let formats = Set(publications.map(\.format))
        // Comics, an ebook and a PDF all come out of one walk. A scan that only
        // finds one family is the common way this goes wrong.
        #expect(formats.contains(.cbz))
        #expect(formats.contains(.cbt))
        #expect(formats.contains(.cbr))
        #expect(formats.contains(.pdf))
        #expect(formats.contains(.epub))
    }

    @Test("Subdirectories are walked")
    func recursive() async throws {
        // The corpus keeps comics and ebooks in sibling folders, so finding both
        // proves the walk descended rather than reading only the top level.
        let publications = await LibraryScanner.scanAll(folderAt: corpus)
        #expect(publications.contains { $0.format == .epub })
        #expect(publications.contains { $0.format == .cbz })
    }

    @Test("A scan finishes with counts that match what it emitted")
    func finishedCountsMatch() async throws {
        let events = await events(in: corpus)
        let found = events.filter { $0.publication != nil }.count
        let skipped = events.filter { if case .skipped = $0 { return true } else { return false } }
            .count

        guard case let .finished(reportedFound, reportedSkipped) = events.last else {
            Issue.record("the scan did not finish")
            return
        }
        // A progress count that disagrees with the rows on screen is worse than no
        // count at all.
        #expect(reportedFound == found)
        #expect(reportedSkipped == skipped)
    }

    @Test("Publications are emitted before the scan finishes")
    func emitsProgressively() async throws {
        // `local-library` requires browsing what is already found while the scan
        // continues, which is only possible if rows arrive before the end.
        var sawPublicationBeforeFinish = false
        for await event in LibraryScanner.scan(folderAt: corpus) {
            if case .finished = event { break }
            if event.publication != nil { sawPublicationBeforeFinish = true }
        }
        #expect(sawPublicationBeforeFinish)
    }

    @Test("An unreadable file is skipped with a reason, not dropped silently")
    func skipsWithReason() async throws {
        let events = await events(in: corpus)
        let skips = events.compactMap { event -> (String, String)? in
            if case let .skipped(path, reason) = event { return (path, reason) }
            return nil
        }
        // refused.cb7 is in the corpus and must be reported by name.
        let sevenZip = skips.first { $0.0 == "refused.cb7" }
        #expect(sevenZip != nil)
        #expect(sevenZip?.1.contains("CB7") == true)
        #expect(skips.allSatisfy { !$0.1.isEmpty })
    }

    @Test("A refused publication is found rather than skipped")
    func refusedIsFound() async throws {
        // rar4-solid.cbr cannot be opened, but the library should list it and say
        // why — so the scan reports it as found, marked unopenable.
        let publications = await LibraryScanner.scanAll(folderAt: corpus)
        let refused = publications.filter { !$0.isOpenable }
        #expect(!refused.isEmpty)
    }

    @Test("Cancelling the consumer stops the walk")
    func cancellable() async throws {
        // `local-library` requires the scan to be cancellable. Breaking out of the
        // loop terminates the stream, which cancels the task behind it.
        var seen = 0
        for await event in LibraryScanner.scan(folderAt: corpus) where event.publication != nil {
            seen += 1
            if seen == 2 { break }
        }
        #expect(seen == 2)
    }

    // MARK: - Folders as publications

    @Test("A folder of images is one publication, not a shelf")
    func imageFolderIsOnePublication() async throws {
        try await withTemporaryFolder { root in
            let comic = root.appending(path: "Some Comic")
            try FileManager.default.createDirectory(at: comic, withIntermediateDirectories: true)
            for index in 1...3 {
                try Data(Self.png).write(to: comic.appending(path: "p\(index).png"))
            }

            let publications = await LibraryScanner.scanAll(folderAt: root)
            #expect(publications.count == 1)
            #expect(publications.first?.format == .imageFolder)
            #expect(publications.first?.pageCount == 3)
        }
    }

    @Test("A folder of comics is a shelf, and each comic is its own publication")
    func folderOfComicsIsAShelf() async throws {
        try await withTemporaryFolder { root in
            let shelf = root.appending(path: "Series Name")
            try FileManager.default.createDirectory(at: shelf, withIntermediateDirectories: true)
            for name in ["Series 001.cbz", "Series 002.cbz"] {
                try Data(contentsOf: FixtureCorpus.url("comics/natural-sort.cbz"))
                    .write(to: shelf.appending(path: name))
            }

            let publications = await LibraryScanner.scanAll(folderAt: root)
            // Two publications, not one folder-shaped one — the directory holds
            // publications rather than pages.
            #expect(publications.count == 2)
            #expect(publications.allSatisfy { $0.format == .cbz })
            #expect(publications.map(\.number).sorted { ($0 ?? "") < ($1 ?? "") } == ["1", "2"])
        }
    }

    @Test("An empty folder yields nothing and still finishes")
    func emptyFolder() async throws {
        try await withTemporaryFolder { root in
            let events = await self.events(in: root)
            #expect(events == [.finished(found: 0, skipped: 0)])
        }
    }

    @Test("A folder that does not exist finishes rather than hanging")
    func missingFolder() async throws {
        let events = await events(in: URL(fileURLWithPath: "/nowhere/at/all"))
        #expect(events == [.finished(found: 0, skipped: 0)])
    }

    // MARK: - Helpers

    private static let png: [UInt8] = [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x03,
        0x08, 0x02, 0x00, 0x00, 0x00, 0x8D, 0x6F, 0x26,
        0xD5, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41,
        0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
        0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xDD, 0x8D,
        0xB0, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,
        0x44, 0xAE, 0x42, 0x60, 0x82,
    ]

    private func withTemporaryFolder(_ body: (URL) async throws -> Void) async throws {
        let root = URL.temporaryDirectory.appending(path: "scan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await body(root)
    }
}
