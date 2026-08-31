import Foundation
import Testing

@testable import Formats
import StoryArcCore

/// An audiobook reaching the library as a publication, and a locked one not reaching it.
///
/// Every audio container used to stop at a named refusal here. These are the assertions
/// that say it does not any more — and the one that says the locked file still does, for a
/// different reason and in different words.
@Suite("Audiobook indexing")
struct AudiobookIndexingTests {

    private let corpus = FixtureCorpus.root.appending(path: "audiobooks")

    @Test("A chaptered M4B opens as a publication whose parts are its chapters")
    func chapteredOpens() async throws {
        let book = try await PublicationIndexer.index(fileAt: corpus.appending(path: "chaptered.m4b"))
        #expect(book.format == .audiobook)
        #expect(book.format.isAudio)
        #expect(book.pageCount == 3, "three parts, from the container's own chapter atom")
        #expect(book.skippedPageCount == 0)
        #expect(!book.format.isPagedImages, "nothing pages through minutes")
    }

    /// `publication-formats`: "nothing is reported as missing, because an unchaptered
    /// audiobook is a normal audiobook".
    @Test("An unchaptered audiobook opens, and reports nothing missing")
    func unchapteredOpens() async throws {
        let book = try await PublicationIndexer.index(fileAt: corpus.appending(path: "unchaptered.m4a"))
        #expect(book.format == .audiobook)
        #expect(book.pageCount == 1)
        #expect(book.skippedPageCount == 0)
        #expect(!book.isPartial)
    }

    @Test("A folder of audio opens as one audiobook, not as a comic")
    func folderOpens() async throws {
        let book = try await PublicationIndexer.index(fileAt: corpus.appending(path: "folder-parts"))
        #expect(book.format == .audioFolder)
        #expect(book.pageCount == 3)
    }

    /// The folder holds two audio files and one image, and `FolderKind`'s majority rule
    /// makes it an audiobook. This asserts the indexer acts on that answer rather than
    /// opening a one-page comic.
    @Test("A folder that is mostly audio opens as an audiobook")
    func mixedFolderOpens() async throws {
        let book = try await PublicationIndexer.index(fileAt: corpus.appending(path: "mixed-folder"))
        #expect(book.format == .audioFolder)
        #expect(book.pageCount == 2, "the image is not a part")
    }

    /// A tie is a comic, and a folder of images still is one. The audiobook path must not
    /// have taken folders away from the reader — this is the regression that would show it.
    @Test("A folder of images is still a comic")
    func imageFolderIsStillAComic() async throws {
        let folder = try scratchFolder()
        // A one-by-one PNG, which is all the indexer needs to count a page.
        let png = Data(base64Encoded: """
            iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmM\
            IQAAAABJRU5ErkJggg==
            """)
        let page = try #require(png)
        try page.write(to: folder.appending(path: "page1.png"))
        try page.write(to: folder.appending(path: "page2.png"))

        let comic = try await PublicationIndexer.index(fileAt: folder)
        #expect(comic.format == .imageFolder)
        #expect(!comic.format.isAudio)
    }

    // MARK: - The refusal that is not an unsupported container

    /// `publication-formats`: the app "states that the file is protected by its store's
    /// content protection and that StoryArc cannot open it, naming that as the reason … it
    /// does not prompt for a key, an account or an activation code … and the refusal is
    /// distinct from an unsupported container".
    ///
    /// `protected.aax` still holds a **decodable** stream, so a decoder that merely choked
    /// would not satisfy this. The brand at offset 8 is what decides.
    @Test("A protected audiobook is refused for being locked, not for being unsupported")
    func protectedIsRefusedByName() async throws {
        await #expect(throws: PublicationIndexer.IndexError.contentProtected) {
            try await PublicationIndexer.index(fileAt: corpus.appending(path: "protected.aax"))
        }
    }

    /// The two refusals must not collapse into one. A CB7 is a container StoryArc does not
    /// read; an `.aax` is a container it *does* read, holding a file nobody without the
    /// store's key can open, and the reader can only act on the difference if it is stated.
    @Test("The locked refusal is a different value from the unsupported one")
    func theTwoRefusalsAreDistinct() {
        let locked = PublicationIndexer.IndexError.contentProtected
        #expect(locked != .unsupported(format: "MPEG-4 audio"))
        #expect(locked != .unsupported(format: "protected audiobook"))
        #expect(locked != .unreadable(reason: "the archive could not be read"))
    }

    /// The refusal carries no payload, and that is deliberate: there is no key to ask for
    /// and no account to name, so there is nowhere for a prompt to get its wording from.
    @Test("Nothing in the refusal invites a prompt for a key or an account")
    func nothingToPromptFor() {
        let reason = LibraryScanner.skipReason(for: .contentProtected)
        #expect(reason.contains("content protection"))
        for word in ["key", "account", "activation", "password", "sign in", "log in"] {
            #expect(!reason.lowercased().contains(word), "the refusal must not mention a \(word)")
        }
    }

    // MARK: - Damage

    /// `publication-formats`: a damaged audiobook "plays what it can and states how much it
    /// could not". A folder is where the count is answerable before playback.
    @Test("A folder with an undecodable part is partial, not refused")
    func partialFolder() async throws {
        let folder = try scratchFolder()
        try FileManager.default.copyItem(
            at: corpus.appending(path: "folder-parts/part1.mp3"),
            to: folder.appending(path: "part1.mp3")
        )
        try Data("not audio at all".utf8).write(to: folder.appending(path: "part2.mp3"))

        let book = try await PublicationIndexer.index(fileAt: folder)
        #expect(book.format == .audioFolder)
        #expect(book.pageCount == 1, "what it can")
        #expect(book.skippedPageCount == 1, "and how much it could not")
        #expect(book.isPartial, "which is the same flag a comic missing pages sets")
    }

    private func scratchFolder() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "indexing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
