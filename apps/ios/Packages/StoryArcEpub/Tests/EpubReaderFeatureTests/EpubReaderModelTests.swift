import Foundation
import Testing

import Persistence
import StoryArcCore
@testable import EpubReaderFeature

/// Opening a reflowable book.
///
/// Runs on a simulator rather than the host: Readium is iOS-only, which is the
/// whole reason this package exists. The fixture is read from the shared corpus by
/// path — a simulator sees the host's filesystem, so nothing has to be copied in.
@MainActor
@Suite("EPUB reader")
struct EpubReaderModelTests {

    private static let corpus: URL = {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            let candidate = dir.appending(path: "packages/test-fixtures")
            if FileManager.default.fileExists(
                atPath: candidate.appending(path: "manifest.json").path
            ) {
                return candidate
            }
            dir = dir.deletingLastPathComponent()
        }
        fatalError("fixture corpus not found above \(#filePath)")
    }()

    private func model(_ name: String) -> EpubReaderModel {
        let url = Self.corpus.appending(path: "ebooks/\(name)")
        return EpubReaderModel(
            publication: Publication(
                identity: PublicationIdentity(normalizedPath: url.path),
                format: .epub,
                displayTitle: name,
                origin: .embedded
            ),
            url: url
        )
    }

    @Test("A reflowable EPUB opens and gets a navigator")
    func opensAnEpub() async {
        let reader = model("fixture.epub")
        await reader.open()

        #expect(reader.failure == nil)
        #expect(reader.navigator != nil)
        // Nothing has been read yet, and a percentage is the only progress a
        // reflowable book can honestly report.
        #expect(reader.progression == 0)
    }

    @Test("An EPUB 2 opens too — the older shape is not a different product")
    func opensEpub2() async {
        let reader = model("epub2.epub")
        await reader.open()

        #expect(reader.failure == nil)
        #expect(reader.navigator != nil)
    }

    /// `ebook-reader`, *A publication with nothing to say*: the control is there only once
    /// the walk finds text, and a book of prose has it on its first pages.
    @Test("A book with text offers read-aloud once it opens")
    func offersReadAloud() async {
        let reader = model("fixture.epub")
        await reader.open()

        #expect(reader.canReadAloud)
    }

    @Test("A file that is not a book says so rather than showing a blank page")
    func reportsFailure() async {
        let reader = model("no-package.epub")
        await reader.open()

        #expect(reader.failure != nil)
        #expect(reader.navigator == nil)
    }

    @Test("A finished book reopens at its start, not at the page it was marked finished on")
    func finishedBookReopensAtStart() async throws {
        let base = model("fixture.epub")
        let progress = try ProgressStore.inMemory()
        try await progress.save(
            ReadingProgress(
                identity: base.publication.identity,
                position: .reflowable(
                    progression: 0.87,
                    locator: #"""
                    {"href":"/chapter-1.xhtml","type":"text/html",
                     "locations":{"totalProgression":0.87}}
                    """#
                ),
                isFinished: true,
                updatedAt: Date()
            )
        )

        let reader = EpubReaderModel(publication: base.publication, url: base.url, progress: progress)
        await reader.open()

        #expect(reader.failure == nil)
        // The stored locator sat at 87%, and would win were the record not finished — see
        // the sibling test below.
        #expect(reader.progression == 0)
    }

    @Test("An unfinished book resumes at its stored locator, so the fix above is not a no-op")
    func unfinishedBookResumesAtItsLocator() async throws {
        let base = model("fixture.epub")
        let progress = try ProgressStore.inMemory()
        try await progress.save(
            ReadingProgress(
                identity: base.publication.identity,
                position: .reflowable(
                    progression: 0.87,
                    locator: #"""
                    {"href":"/chapter-1.xhtml","type":"text/html",
                     "locations":{"totalProgression":0.87}}
                    """#
                ),
                isFinished: false,
                updatedAt: Date()
            )
        )

        let reader = EpubReaderModel(publication: base.publication, url: base.url, progress: progress)
        await reader.open()

        #expect(reader.failure == nil)
        #expect(reader.progression == 0.87)
    }

    @Test("A position with no locator -- a pull's own kind -- still opens at its fraction")
    func aPositionWithNoLocatorOpensAtItsFraction() async throws {
        // The defect: `KavitaSync.pull` used to write a page number over an EPUB's own
        // position, and a page is not a locator this reader can open -- so the book
        // opened at its very first page regardless of how far a server said the reader
        // had gone. `KavitaExchange.position(readingTo:of:like:)` now writes a fraction
        // with an empty locator instead, which is exactly this shape.
        let base = model("fixture.epub")
        let progress = try ProgressStore.inMemory()
        try await progress.save(
            ReadingProgress(
                identity: base.publication.identity,
                position: .reflowable(progression: 0.6, locator: ""),
                isFinished: false,
                updatedAt: Date()
            )
        )

        let reader = EpubReaderModel(publication: base.publication, url: base.url, progress: progress)
        await reader.open()

        #expect(reader.failure == nil)
        #expect(reader.progression > 0, "opened at the first page despite the recorded fraction")
    }
}
