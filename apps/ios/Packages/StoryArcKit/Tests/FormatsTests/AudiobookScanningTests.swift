import Foundation
import Testing

@testable import Formats
import StoryArcCore

/// What a walk makes of audio it finds in a folder.
///
/// The unit under test is the *shelf-or-publication* decision, which `LibraryScanner` makes
/// per directory and which nothing else can make: `FolderKind` answers what a folder is
/// once somebody has decided the folder is the unit, and this is where that is decided.
@Suite("Audiobook scanning")
struct AudiobookScanningTests {

    private let corpus = FixtureCorpus.root.appending(path: "audiobooks")

    /// **The regression a screenshot found and no unit test did.**
    ///
    /// A picked library holds its publications one directory down and one stray `.m4b` at
    /// its top level. The top level therefore has no *packed* publication, so the audio
    /// branch claimed the whole folder, its subdirectories were never walked, and a shelf of
    /// fifteen comics became one row reading "Audio folder".
    ///
    /// A folder of ordered audio has no subdirectories. A folder that has them is a place
    /// where publications live, and the audio at its top level is one book each.
    @Test("A library folder with one audiobook in it is still a library")
    func oneAudiobookDoesNotSwallowTheLibrary() async throws {
        let library = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: library) }
        try FileManager.default.copyItem(
            at: corpus.appending(path: "unchaptered.m4a"),
            to: library.appending(path: "Sea Room.m4a")
        )
        let inside = library.appending(path: "Comics")
        try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: FixtureCorpus.root.appending(path: "comics/single-page.cbz"),
            to: inside.appending(path: "single-page.cbz")
        )

        let found = await LibraryScanner.scanAll(folderAt: library)
        #expect(found.count == 2, "the audiobook and the comic, not one folder pretending to be a book")
        #expect(found.contains { $0.format == .audiobook })
        #expect(found.contains { $0.format == .cbz })
        #expect(!found.contains { $0.format == .audioFolder }, "the library is not itself an audiobook")
    }

    /// The other half of the same rule: a folder that really is a folder of parts.
    @Test("A folder of parts and nothing else is one audiobook")
    func aFolderOfPartsIsOneBook() async throws {
        let library = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: library) }
        let book = library.appending(path: "The Peregrine")
        try FileManager.default.copyItem(at: corpus.appending(path: "folder-parts"), to: book)

        let found = await LibraryScanner.scanAll(folderAt: library)
        #expect(found.count == 1)
        #expect(found.first?.format == .audioFolder)
        #expect(found.first?.pageCount == 3, "three parts, not three publications")
    }

    /// A folder of audio beside a folder of images stays two publications.
    @Test("Two folders are two publications")
    func twoFolders() async throws {
        let library = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: library) }
        try FileManager.default.copyItem(
            at: corpus.appending(path: "folder-parts"),
            to: library.appending(path: "The Peregrine")
        )
        let comic = library.appending(path: "Salt and Iron")
        try FileManager.default.createDirectory(at: comic, withIntermediateDirectories: true)
        let page = try #require(Data(base64Encoded: """
            iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmM\
            IQAAAABJRU5ErkJggg==
            """))
        try page.write(to: comic.appending(path: "page1.png"))
        try page.write(to: comic.appending(path: "page2.png"))

        let found = await LibraryScanner.scanAll(folderAt: library)
        #expect(Set(found.map(\.format)) == [.audioFolder, .imageFolder])
    }

    // MARK: - A locked file the walk never opened

    /// `publication-formats`: a store-locked audiobook "is refused **by name**", stating the
    /// content protection as the reason.
    ///
    /// **Android found this on a device and iOS had it too.** The sniffer names a locked file
    /// by its `aavd` brand and `PublicationIndexer` throws `.contentProtected` for it — both
    /// asserted, both true, and both reached only by a caller that opens the file. A scanned
    /// folder never did: `.aax` is in neither ``LibraryScanner/candidateExtensions`` nor
    /// ``FolderKind/audioExtensions``, and the walk indexes `publicationFiles + audioFiles`.
    /// So a protected audiobook produced no row, no skip and no count — it was not refused by
    /// name, it was not refused at all, and the reader saw an empty shelf.
    @Test("A protected audiobook is refused by name rather than dropped in silence")
    func aProtectedAudiobookIsRefusedByName() async throws {
        let library = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: library) }
        try FileManager.default.copyItem(
            at: corpus.appending(path: "protected.aax"),
            to: library.appending(path: "Sea Room.aax")
        )

        var skipped: [(path: String, reason: String)] = []
        var found = 0
        for await event in LibraryScanner.scan(folderAt: library) {
            switch event {
            case .found: found += 1
            case let .skipped(path, reason): skipped.append((path, reason))
            case .finished: break
            }
        }

        #expect(found == 0, "a locked file is not a publication")
        #expect(skipped.count == 1, "and it is not nothing either — it was dropped in silence")
        #expect(skipped.first?.path.hasSuffix("Sea Room.aax") == true)
        let reason = try #require(skipped.first?.reason)
        #expect(reason.contains("content protection"), "the reason is the lock, not the container")
        // The refusal prompts for nothing, here as everywhere else it is worded.
        for asked in ["key", "account", "activation", "password", "sign in"] {
            #expect(!reason.lowercased().contains(asked), "the scan reason asked for a \(asked)")
        }
    }

    /// The half that makes the fix safe: a locked file is worth *opening* and is not a part.
    ///
    /// Android records the same distinction — the extension is "a hint about what is worth
    /// opening, kept apart from the playable set so a locked file cannot become a folder's
    /// chapter". Without it, a folder holding parts and one `.aax` would either count the
    /// locked file as a chapter nothing can decode, or stop being a folder of parts at all.
    @Test("A locked file beside a folder's parts is not one of its parts")
    func aLockedFileIsNotAPart() async throws {
        let library = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: library) }
        let book = library.appending(path: "The Peregrine")
        try FileManager.default.copyItem(at: corpus.appending(path: "folder-parts"), to: book)
        try FileManager.default.copyItem(
            at: corpus.appending(path: "protected.aax"),
            to: book.appending(path: "bonus.aax")
        )

        let found = await LibraryScanner.scanAll(folderAt: library)
        #expect(found.count == 1, "still one audiobook, not a shelf")
        #expect(found.first?.format == .audioFolder)
        #expect(found.first?.pageCount == 3, "three parts — the locked file is not a fourth")
    }

    /// A directory of this test's own, which **the caller must remove**.
    ///
    /// Every call site carries `defer { try? FileManager.default.removeItem(at: library) }`,
    /// and they carry it because nothing used to: 634 `scan-*` directories were sitting in the
    /// system temp folder, one per test per run since this file was written. A temp directory
    /// is not free — the system purges `/var/folders/…/T` on its own schedule and not on ours,
    /// so between purges a machine accumulates them, and a suite that leaks state on disk is a
    /// suite that will eventually fail for a reason that is not in its own source.
    ///
    /// A `defer` per call rather than a shared teardown, because a `struct` suite has no
    /// `deinit` to hang one on and turning this into a `final class` to get one would change
    /// how the suite is isolated for a housekeeping reason.
    private func scratchFolder() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "scan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
