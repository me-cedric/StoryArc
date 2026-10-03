import Foundation
import Testing

@testable import Formats

/// Task 16.9, `audio-playback`: an audiobook's own cover, read once at index time.
///
/// Against the shared corpus, the same fixtures Android asserts the identical behaviour
/// against — `with-cover.m4b` carries its artwork as an MP4 `covr` atom, `with-cover.mp3` as
/// an ID3 `APIC` frame, and `mixed-folder` carries a loose `cover.png` beside its tracks.
@Suite("Audiobook cover")
struct AudiobookCoverTests {

    private let corpus = FixtureCorpus.root.appending(path: "audiobooks")

    // MARK: - Embedded artwork

    @Test("An M4B's own covr atom is read as its cover")
    func m4bCovrAtom() async throws {
        let data = await AudiobookCover.embedded(in: corpus.appending(path: "with-cover.m4b"))
        #expect(data != nil)
        #expect((data?.count ?? 0) > 0)
    }

    @Test("The same cover as an ID3 APIC frame is read identically")
    func mp3ApicFrame() async throws {
        let data = await AudiobookCover.embedded(in: corpus.appending(path: "with-cover.mp3"))
        #expect(data != nil)
        #expect((data?.count ?? 0) > 0)
    }

    @Test("An audiobook with no embedded artwork names no cover")
    func noEmbeddedArtwork() async throws {
        let data = await AudiobookCover.embedded(in: corpus.appending(path: "chaptered.m4b"))
        #expect(data == nil)
    }

    // MARK: - A folder's own loose cover

    @Test("A folder's own cover.png is found beside its tracks")
    func folderCover() {
        let found = AudiobookCover.inFolder(at: corpus.appending(path: "mixed-folder"))
        #expect(found?.lastPathComponent == "cover.png")
    }

    @Test("A folder with no loose cover names none")
    func folderWithNoCover() {
        let found = AudiobookCover.inFolder(at: corpus.appending(path: "folder-parts"))
        #expect(found == nil)
    }

    // MARK: - The store

    @Test("Written artwork is read back byte for byte")
    func storeRoundTrips() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "audiobook-cover-store-\(UUID().uuidString)")
        let store = AudiobookCoverStore(directory: directory)
        let source = corpus.appending(path: "with-cover.m4b")
        let data = try #require(await AudiobookCover.embedded(in: source))

        let path = try #require(store.write(data, for: source))
        let written = try Data(contentsOf: URL(fileURLWithPath: path))
        #expect(written == data)

        try? FileManager.default.removeItem(at: directory)
    }

    @Test("Writing the same source twice replaces rather than accumulates")
    func storeReplacesRatherThanAccumulates() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "audiobook-cover-store-\(UUID().uuidString)")
        let store = AudiobookCoverStore(directory: directory)
        let source = corpus.appending(path: "with-cover.m4b")

        let first = try #require(store.write(Data("one".utf8), for: source))
        let second = try #require(store.write(Data("two".utf8), for: source))
        #expect(first == second)
        #expect(try Data(contentsOf: URL(fileURLWithPath: second)) == Data("two".utf8))

        let entries = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(entries.count == 1, "one source, one file, however many times it is written")

        try? FileManager.default.removeItem(at: directory)
    }
}
