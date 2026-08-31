import Foundation
import Testing

@testable import Formats

/// Reading an audiobook's parts, asserted against the shared corpus.
///
/// The expectations come from `packages/test-fixtures/manifest.json` under `audiobooks`,
/// and Android asserts the same numbers against the same files. Everything here reads from
/// disk rather than from a literal, so regenerating the corpus differently fails it.
@Suite("Audiobook reader")
struct AudiobookReaderTests {

    private let corpus = FixtureCorpus.root.appending(path: "audiobooks")

    // MARK: - Chapters from the container's own markers

    @Test("An M4B's chapters come from the container's own atom")
    func chapteredM4B() async throws {
        let book = await AudiobookReader.read(fileAt: corpus.appending(path: "chaptered.m4b"))
        #expect(book.parts.map(\.title) == ["One", "Two", "Three"])
        #expect(book.parts.map(\.start) == [0, 2, 4])
        #expect(book.parts.allSatisfy { $0.duration == 2 })
        #expect(book.unreadablePartCount == 0)
    }

    /// The same three chapters in the other container, which fails differently. A corpus
    /// with only one of the two would hide it — and did, on Android, where MP4 chapter
    /// atoms need a media3 bump that ID3 frames do not.
    @Test("The same chapters as ID3 CHAP frames read identically")
    func chapteredMP3() async throws {
        let book = await AudiobookReader.read(fileAt: corpus.appending(path: "id3-chapters.mp3"))
        #expect(book.parts.map(\.title) == ["One", "Two", "Three"])
        #expect(book.parts.map(\.start) == [0, 2, 4])
    }

    /// `publication-formats`: an unchaptered audiobook "opens, and its parts — the files, or
    /// the whole of a single file — stand in for chapters … nothing is reported as missing,
    /// because an unchaptered audiobook is a normal audiobook".
    @Test("An audiobook with no chapter markers is one part, and nothing is missing")
    func unchaptered() async throws {
        let book = await AudiobookReader.read(fileAt: corpus.appending(path: "unchaptered.m4a"))
        #expect(book.parts.count == 1, "one part, never zero — an empty list is a list of nothing to play")
        #expect(book.parts.first?.title == nil, "unnamed, rather than named after the file")
        #expect(book.parts.first?.start == 0)
        #expect(book.unreadablePartCount == 0, "nothing is reported as missing")
        let duration = try #require(book.parts.first?.duration)
        #expect(duration > 4.5 && duration < 5.5, "about five seconds, per the manifest")
    }

    /// `publication-formats`: "an `.m4b` and an `.m4a` holding the same audio are treated
    /// identically, because the extension is a hint and the contents are the fact".
    @Test("The extension decides nothing")
    func extensionIsAHint() async throws {
        let asM4A = await AudiobookReader.read(fileAt: corpus.appending(path: "unchaptered.m4a"))
        let renamed = try renamed(corpus.appending(path: "unchaptered.m4a"), to: "unchaptered.m4b")
        let asM4B = await AudiobookReader.read(fileAt: renamed)
        #expect(asM4A.parts.count == asM4B.parts.count)
        #expect(asM4A.parts.first?.duration == asM4B.parts.first?.duration)
    }

    // MARK: - A folder of parts

    /// `publication-formats`: a folder of audio "is treated as a single audiobook whose
    /// parts play in that order, by the same ordering rule that makes a folder of images one
    /// comic" — which is the natural sort that puts `part10` after `part2`.
    @Test("A folder's parts play in natural order, not lexical order")
    func folderParts() async throws {
        let book = await AudiobookReader.read(folderAt: corpus.appending(path: "folder-parts"))
        #expect(book.parts.map { $0.url.lastPathComponent } == ["part1.mp3", "part2.mp3", "part10.mp3"])
        #expect(book.parts.allSatisfy { $0.start == 0 }, "each part is a whole file, so each starts at zero")
        #expect(book.unreadablePartCount == 0)
    }

    @Test("A folder's parts are named for the chapter, never for the file")
    func folderPartsAreUnnamed() async throws {
        let book = await AudiobookReader.read(folderAt: corpus.appending(path: "folder-parts"))
        #expect(
            book.parts.allSatisfy { $0.title == nil },
            "`01 - track.mp3` is not what a listener is in the middle of — design.md records that as a product decision"
        )
    }

    /// The image in `mixed-folder` is not a part. `FolderKind` has already decided the folder
    /// is an audiobook; this is the other half — what plays once it has.
    @Test("A mixed folder plays only its audio")
    func mixedFolder() async throws {
        let book = await AudiobookReader.read(folderAt: corpus.appending(path: "mixed-folder"))
        #expect(book.parts.map { $0.url.lastPathComponent } == ["part1.mp3", "part2.mp3"])
    }

    // MARK: - Damage

    /// `publication-formats`: a damaged audiobook "plays what it can and states how much it
    /// could not". A folder is where that is answerable before playback: an entry that will
    /// not load is one part lost, and the rest still play.
    @Test("A folder part that cannot be decoded is counted, and the rest still play")
    func folderWithAnUnreadablePart() async throws {
        let folder = try scratchFolder()
        try FileManager.default.copyItem(
            at: corpus.appending(path: "folder-parts/part1.mp3"),
            to: folder.appending(path: "part1.mp3")
        )
        try Data("not audio at all".utf8).write(to: folder.appending(path: "part2.mp3"))

        let book = await AudiobookReader.read(folderAt: folder)
        #expect(book.parts.count == 1, "what it can")
        #expect(book.unreadablePartCount == 1, "and how much it could not")
    }

    /// The header parses and the media does not finish. `+faststart` puts the `moov` at the
    /// front on purpose, so this file opens rather than being damaged beyond opening — which
    /// is what the corpus's own note records about the first attempt at this fixture.
    @Test("A truncated audiobook still opens, with its chapters intact")
    func truncated() async throws {
        let book = await AudiobookReader.read(fileAt: corpus.appending(path: "truncated.m4b"))
        #expect(book.parts.map(\.title) == ["One", "Two", "Three"])
    }

    // MARK: - Helpers

    private func scratchFolder() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "audiobook-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func renamed(_ url: URL, to name: String) throws -> URL {
        let folder = try scratchFolder()
        let target = folder.appending(path: name)
        try FileManager.default.copyItem(at: url, to: target)
        return target
    }
}
