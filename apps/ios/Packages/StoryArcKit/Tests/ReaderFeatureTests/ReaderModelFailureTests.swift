import Foundation
import Testing

import Persistence
import StoryArcCore
@testable import ReaderFeature

/// What the reader says when a publication will not open.
///
/// Split out of `ReaderModelTests.swift`, which had reached the 400-line cap this project
/// enforces — wording for a refusal is a seam of its own, separate from the open/decode/move
/// loop the rest of that suite covers.
@MainActor
@Suite("Reader model failure wording")
struct ReaderModelFailureTests {
    /// Walks up from this file to the shared corpus, the same way `ReaderModelTests` does.
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

    private func url(_ relativePath: String) -> URL {
        Self.corpus.appending(path: relativePath)
    }

    private func publication(_ format: PublicationFormat, at url: URL) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: url.path),
            format: format,
            displayTitle: url.lastPathComponent,
            origin: .inferred
        )
    }

    @Test("A publication that cannot be opened says so rather than showing nothing")
    func reportsFailure() async {
        let location = url("comics/refused.cb7")
        let model = ReaderModel(publication: publication(.cb7, at: location), url: location)

        await model.open(maxPixelSize: 256)

        #expect(model.failure != nil)
        #expect(model.pages.isEmpty)
        // "States which formats it does support", per `publication-formats`: a bare "not a
        // format StoryArc reads" is the generic failure that scenario forbids.
        #expect(model.failure?.contains("CBZ") == true, "\(model.failure ?? "nil") names no format.")
        // Open-in names the container it detected, and the reader names it too.
        #expect(model.failure?.contains("7-Zip") == true, "\(model.failure ?? "nil") names no container.")
    }

    @Test("An open failure outside the archive errors shows the fixed sentence, never the raw Swift error")
    func openFailureHidesTheRawError() async {
        // No `InterfaceLanguage.choose` here: this case suspends, and a choice held across a
        // suspension is the leak `ChosenLanguageFormattingTests` describes.
        // Not a PDF, so PdfPageRenderer throws an error that is not a ComicArchiveError.
        let location = url("comics/refused.cb7")
        let model = ReaderModel(publication: publication(.pdf, at: location), url: location)

        await model.open(maxPixelSize: 256)

        #expect(model.failure == "This title could not be opened.")
    }

    @Test("A typed archive error is named, not shown as a raw case")
    func typedArchiveErrorsAreNamed() async {
        // The reader used to show `String(describing: error)` — a raw Swift case name such
        // as "solidArchive" — for any file that reached it without going through the
        // library index first. `publication-formats` requires the same named sentence
        // Open-in and the library already show.
        let location = url("comics/password-protected.cbz")
        let model = ReaderModel(publication: publication(.cbz, at: location), url: location)

        await model.open(maxPixelSize: 256)

        #expect(model.failure != "passwordProtected", "the raw case name leaked to the reader")
        #expect(model.failure?.contains("password") == true)
    }

    @Test("A solid archive reaching the reader is named, not shown as a raw case")
    func solidArchiveIsNamed() async {
        let location = url("comics/rar4-solid.cbr")
        let model = ReaderModel(publication: publication(.cbr, at: location), url: location)

        await model.open(maxPixelSize: 256)

        #expect(model.failure != "solidArchive", "the raw case name leaked to the reader")
        #expect(model.failure?.contains("solid compression") == true)
    }
}
