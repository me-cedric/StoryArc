import Foundation
import Testing

@testable import Formats

/// A refusal is a case, not a sentence.
///
/// `localization`'s *A refusal speaks the reader's language* and *A sentence built around
/// content*: the words a reader is shown come from the module that draws them, and the
/// format layer only says **which** refusal this is. `PublicationIndexer.IndexError` used to
/// carry `unreadable(reason: String)`, and seven English sentences were written into it —
/// where no string catalogue can reach them and `pnpm strings:ios` cannot see them.
///
/// This suite drives the real corpus and asserts the case. It says nothing about words,
/// which is the point: `SkipReasonWordsTests` in `LibraryFeature` owns those, because that is
/// the module with a catalogue.
///
/// Android's `SkipReasonIsClosedTest` asserts the same case names against the same fixtures.
/// The two case sets are checked by reading, so a name that differs between them is a defect.
@Suite("A refusal the scan reports is a closed case")
struct SkipReasonIsClosedTests {
    private var corpus: URL { FixtureCorpus.root }

    /// A folder holding just the files a test names, so the assertions do not depend on
    /// everything else the corpus happens to contain.
    private func folder(_ files: [String]) throws -> URL {
        let root = URL.temporaryDirectory.appending(path: "skips-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for file in files {
            try FileManager.default.copyItem(
                at: corpus.appending(path: file),
                to: root.appending(path: (file as NSString).lastPathComponent)
            )
        }
        return root
    }

    /// A file whose bytes are what the test needs them to be.
    private func file(named name: String, holding bytes: String) throws -> URL {
        let root = URL.temporaryDirectory.appending(path: "skips-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appending(path: name)
        try Data(bytes.utf8).write(to: url)
        return url
    }

    @Test("A file that is not there is its own case")
    func notThere() async {
        let missing = URL.temporaryDirectory.appending(path: "gone-\(UUID().uuidString).cbz")

        await #expect(throws: PublicationIndexer.IndexError.notThere) {
            _ = try await PublicationIndexer.index(fileAt: missing)
        }
    }

    @Test("Bytes no sniffer recognises are their own case")
    func formatNotRecognised() async throws {
        let url = try file(named: "garbage.cbz", holding: "this is not an archive")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        await #expect(throws: PublicationIndexer.IndexError.formatNotRecognised) {
            _ = try await PublicationIndexer.index(fileAt: url)
        }
    }

    @Test("A password-protected archive is its own case")
    func archivePasswordProtected() async throws {
        let url = corpus.appending(path: "comics/password-protected.cbz")

        await #expect(throws: PublicationIndexer.IndexError.archivePasswordProtected) {
            _ = try await PublicationIndexer.index(fileAt: url)
        }
    }

    @Test("A PDF that will not open is its own case")
    func pdfUnopenable() async throws {
        let url = try file(named: "broken.pdf", holding: "%PDF-1.7\n")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        await #expect(throws: PublicationIndexer.IndexError.pdfUnopenable) {
            _ = try await PublicationIndexer.index(fileAt: url)
        }
    }

    @Test("A container StoryArc does not read names itself, and the name is content")
    func unsupportedNamesTheFormat() async throws {
        let url = corpus.appending(path: "comics/refused.cb7")

        await #expect(throws: PublicationIndexer.IndexError.unsupported(format: "CB7")) {
            _ = try await PublicationIndexer.index(fileAt: url)
        }
    }

    @Test("A locked audiobook is its own case and carries no key to ask for")
    func contentProtected() async throws {
        let url = corpus.appending(path: "audiobooks/protected.aax")

        await #expect(throws: PublicationIndexer.IndexError.contentProtected) {
            _ = try await PublicationIndexer.index(fileAt: url)
        }
    }

    /// The seam this change closes: what the scan hands the library.
    ///
    /// Three refusals of three kinds in one walk, each arriving as a case. A list where one
    /// row is translated and another is not is the mixture `localization`'s *Reasons of
    /// different kinds in one list* forbids, and it is only avoidable if every row is a case
    /// the drawing module can word.
    @Test("A scan reports every refusal as a case the library can word")
    func aScanReportsCases() async throws {
        let root = try folder([
            "comics/refused.cb7",
            "comics/password-protected.cbz",
            "audiobooks/protected.aax",
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        var reasons: [String: SkipReason] = [:]
        for await event in LibraryScanner.scan(folderAt: root) {
            if case let .skipped(path, reason) = event { reasons[path] = reason }
        }

        #expect(reasons["refused.cb7"] == .unsupportedFormat("CB7"))
        #expect(reasons["password-protected.cbz"] == .archivePasswordProtected)
        #expect(reasons["protected.aax"] == .contentProtected)
        // The catch-all is for a failure nothing wrote a sentence for. A refusal the layer
        // does have a case for must never arrive as one, or the reader is told nothing.
        #expect(!reasons.values.contains(.unknown))
    }
}
