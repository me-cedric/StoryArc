import Foundation
import Testing

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

    @Test("A file that is not a book says so rather than showing a blank page")
    func reportsFailure() async {
        let reader = model("no-package.epub")
        await reader.open()

        #expect(reader.failure != nil)
        #expect(reader.navigator == nil)
    }
}
