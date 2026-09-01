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

    private func scratchFolder() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "scan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
