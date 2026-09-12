import Foundation
import Synchronization
import Testing

@testable import Formats

/// A server that answers ranges honestly, serving one fixture's bytes.
///
/// The dishonest ones are ``FakeServer``'s business. This suite is about what happens *above*
/// a source that works, so the only thing asked of this one is that it behaves — until it is
/// unplugged, which is the only way to see a switch that is otherwise invisible.
private final class HonestServer: RangeTransport {
    private let body: Data
    private let unplugged = Mutex(false)

    init(_ body: Data) {
        self.body = body
    }

    /// Set once the transfer has finished, so a later read proves where it came from.
    func unplug() {
        unplugged.withLock { $0 = true }
    }

    struct Unplugged: Error {}

    func fetch(_ url: URL, from: Int64, through: Int64) async throws -> HttpAnswer {
        if unplugged.withLock({ $0 }) { throw Unplugged() }
        let end = min(through, Int64(body.count) - 1)
        let start = Int(from)
        return HttpAnswer(
            status: 206,
            body: body.subdata(in: start..<(Int(end) + 1)),
            contentRange: "bytes \(from)-\(end)/\(body.count)",
            url: url
        )
    }
}

/// `offline-downloads`' *Reading while downloading*, the half that is hard to get right.
///
/// > **THEN** it opens immediately by streaming, and switches to the local copy when the
/// > download completes, **without interrupting reading**
///
/// "Without interrupting" is the claim worth proving, so it is proved against the real corpus
/// rather than against a stub: a comic is opened over a ranged transport, the local copy that
/// a finished download would leave behind is handed over, and the page list and the page bytes
/// are asked whether anything moved.
///
/// Android's `AdoptingArchiveTest` asserts the same cases.
@Suite("A local copy takes over from a stream without moving the reader")
struct AdoptingArchiveTests {
    private static let streamedName = "stored-entries.cbz"
    private static let address = URL(string: "https://books.example/stored-entries.cbz")!

    private let server: HonestServer

    init() throws {
        server = HonestServer(
            try Data(contentsOf: FixtureCorpus.url("comics/\(Self.streamedName)"))
        )
    }

    private func streamed() async throws -> any ComicArchiveReading {
        try await ComicArchiveOpener.open(
            source: try await HttpSource.open(Self.address, transport: server)
        )
    }

    private func onDisk(_ name: String = streamedName) async throws -> any ComicArchiveReading {
        try await ComicArchiveOpener.open(fileAt: FixtureCorpus.url("comics/\(name)"))
    }

    @Test("The local copy takes over and the pages do not move")
    func adoptKeepsThePages() async throws {
        let reading = AdoptingArchive(try await streamed())
        let before = reading.pages

        #expect(reading.adopt(try await onDisk()))

        #expect(reading.pages == before)
        // The switch really happened: with the network gone, a page nobody had read yet
        // still reads. Without this the whole suite passes on an `adopt` that does nothing.
        server.unplug()
        let last = try #require(before.last)
        #expect(try await !reading.data(for: last).isEmpty)
    }

    @Test("The page the reader is on still reads the same bytes afterwards")
    func adoptKeepsTheBytes() async throws {
        let reading = AdoptingArchive(try await streamed())
        // Page 14 is the reader in the scenario. This fixture is shorter, so the page in the
        // middle of it stands in for them — what matters is that it is not page one.
        let page = reading.pages[reading.pages.count / 2]
        let overTheWire = try await reading.data(for: page)

        #expect(reading.adopt(try await onDisk()))
        server.unplug()

        #expect(try await reading.data(for: page) == overTheWire)
    }

    @Test("An archive holding different pages is refused, and nothing moves")
    func differentPagesAreRefused() async throws {
        let reading = AdoptingArchive(try await streamed())
        let before = reading.pages
        let other = try await onDisk("natural-sort.cbz")
        // The guard is only worth having if the two really do disagree.
        #expect(other.pages != before)

        #expect(!reading.adopt(other))

        #expect(reading.pages == before)
        // And the archive still reads, over the transport it was opened on.
        let first = try #require(before.first)
        #expect(try await !reading.data(for: first).isEmpty)
    }

    @Test("A declared spread is still a declared spread through the wrapper")
    func declarationsAreCarried() async throws {
        // `doublePageIndices` and `skippedPageCount` both have a harmless-looking default —
        // no spreads, nothing skipped — so a wrapper that answered for itself would tell the
        // reader a lie the reader cannot check. Both fixtures are chosen for a non-default
        // answer, or these two cases would pass on a wrapper that carried nothing.
        let direct = try await onDisk("manga-metadata.cbz")
        let wrapped = AdoptingArchive(try await onDisk("manga-metadata.cbz"))

        #expect(wrapped.doublePageIndices == [2])
        #expect(wrapped.pages == direct.pages)
        #expect(wrapped.coverPage == direct.coverPage)
    }

    @Test("A skipped page is still counted through the wrapper")
    func skippedPagesAreCarried() async throws {
        let wrapped = AdoptingArchive(try await onDisk("unsupported-codec.cbz"))

        #expect(wrapped.skippedPageCount == 1)
    }
}
