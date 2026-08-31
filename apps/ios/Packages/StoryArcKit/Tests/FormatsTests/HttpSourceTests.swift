import Foundation
import Testing

@testable import Formats

/// A server that answers ranges, and misbehaves on demand.
///
/// The lies are named after the ones `scripts/opds-server.mjs` can be asked to tell, so a
/// case proved here can be watched over the wire against the mock and the two artefacts
/// describe one catalogue of misbehaviour rather than two.
struct FakeServer: RangeTransport {
    enum Lie: Sendable, Equatable {
        /// Answers 200 with the whole resource, ignoring the range.
        case ignore
        /// Answers 200 but sends only the requested slice.
        case status
        /// Answers 206 with the wrong total in `Content-Range`.
        case total
        /// Answers 206 with the bytes of a different range.
        case offset
        /// Answers 206 with fewer bytes than it promised.
        case short
        /// Answers 206 with no `Content-Range` at all.
        case unlabelled
        /// Answers from an address other than the one asked for.
        case moved
        /// Answers 416, as a server whose file shrank would.
        case gone
        /// Answers unhappily.
        case refused(Int)
    }

    let body: Data
    var lie: Lie?

    init(bytes count: Int, lie: Lie? = nil) {
        // Byte `n` is `n % 251`, the same pattern the mock's self-test corpus uses: a
        // window's contents are then arithmetic rather than a second read agreeing with the
        // first, and 251 keeps an off-by-a-block bug off identical bytes.
        self.body = Data((0..<count).map { UInt8($0 % 251) })
        self.lie = lie
    }

    init(body: Data, lie: Lie? = nil) {
        self.body = body
        self.lie = lie
    }

    func fetch(_ url: URL, from: Int64, through: Int64) async throws -> HttpAnswer {
        let count = Int(through - from) + 1
        let total = body.count
        switch lie {
        case .ignore:
            return HttpAnswer(status: 200, body: body, url: url)
        case .status:
            return HttpAnswer(status: 200, body: slice(from: Int(from), count: count), url: url)
        case .gone:
            return HttpAnswer(status: 416, body: Data(), url: url)
        case .refused(let status):
            return HttpAnswer(status: status, body: Data(), url: url)
        case .moved:
            return HttpAnswer(
                status: 206,
                body: slice(from: Int(from), count: count),
                contentRange: "bytes \(from)-\(through)/\(total)",
                url: url.appending(path: "elsewhere")
            )
        case .unlabelled:
            return HttpAnswer(status: 206, body: slice(from: Int(from), count: count), url: url)
        default:
            let start = lie == .offset ? min(Int(from) + 64, max(0, total - count)) : Int(from)
            let sending = lie == .short ? count - 1 : count
            return HttpAnswer(
                status: 206,
                body: slice(from: start, count: sending),
                contentRange: "bytes \(from)-\(through)/\(lie == .total ? total + 1024 : total)",
                url: url
            )
        }
    }

    private func slice(from start: Int, count: Int) -> Data {
        let end = min(start + max(count, 0), body.count)
        guard start < end else { return Data() }
        return body.subdata(in: start..<end)
    }
}

@Suite("Reading over HTTP range requests")
struct HttpSourceTests {
    private let address = URL(string: "https://library.example/files/comic.cbz")!

    private func opened(_ server: FakeServer) async throws -> HttpSource {
        try await HttpSource.open(address, transport: server)
    }

    // MARK: Content-Range

    @Test func aContentRangeIsReadIntoItsThreeNumbers() {
        let range = ContentRange("bytes 0-15/4096")
        #expect(range == ContentRange("bytes 0-15/4096"))
        #expect(range?.start == 0)
        #expect(range?.end == 15)
        #expect(range?.total == 4096)
    }

    /// Every shape that is not a window of bytes that arrived. The 416 form and the
    /// unknown-total form are both legal headers and neither describes a body, so a source
    /// that accepted either would be checking a read against nothing.
    @Test(
        "A Content-Range that describes no arrived bytes is not one",
        arguments: [
            "bytes */4096", "bytes 0-15/*", "items 0-15/4096", "bytes 15-0/4096",
            "bytes 0-15/8", "bytes 0-15", "bytes -1-15/4096", "0-15/4096", "bytes", "",
        ]
    )
    func aMalformedContentRangeIsNoContentRange(header: String) {
        #expect(ContentRange(header) == nil)
    }

    @Test func anAbsentContentRangeIsNoContentRange() {
        #expect(ContentRange(nil) == nil)
    }

    // MARK: Opening

    @Test func openingLearnsTheLengthFromOneByte() async throws {
        let source = try await opened(FakeServer(bytes: 4096))
        #expect(source.length == 4096)
    }

    /// The whole point of probing: a server that will not serve ranges has to be found out
    /// before a reader is waiting on a page, not after. `offline-downloads` then falls back
    /// to downloading first, which is what the app already does.
    @Test func aServerThatIgnoresRangesIsRefusedRatherThanStreamedBadly() async throws {
        await #expect(throws: HttpSourceError.notRanged) {
            try await opened(FakeServer(bytes: 4096, lie: .ignore))
        }
    }

    @Test func a206WithNothingSayingHowLongItIsCannotBeOpened() async throws {
        await #expect(throws: HttpSourceError.unknownLength) {
            try await opened(FakeServer(bytes: 4096, lie: .unlabelled))
        }
    }

    @Test func aRefusalIsNamedWithItsStatus() async throws {
        await #expect(throws: HttpSourceError.refused(status: 404)) {
            try await opened(FakeServer(bytes: 4096, lie: .refused(404)))
        }
    }

    @Test func aRedirectedProbeIsNotTheResourceThatWasAskedFor() async throws {
        await #expect(throws: HttpSourceError.self) {
            try await opened(FakeServer(bytes: 4096, lie: .moved))
        }
    }

    // MARK: Reading

    @Test func aRangeIsTheBytesAskedFor() async throws {
        let server = FakeServer(bytes: 4096)
        let source = try await opened(server)
        let read = try await source.read(offset: 1000, count: 16)
        #expect(read == server.body.subdata(in: 1000..<1016))
    }

    /// The read ADR-0008 makes first: a ZIP keeps its central directory at the end, so the
    /// tail is where every archive is opened from.
    @Test func theTailIsReadableWithoutTheRest() async throws {
        let server = FakeServer(bytes: 4096)
        let source = try await opened(server)
        let (tail, offset) = try await source.readTail(count: 64)
        #expect(offset == 4032)
        #expect(tail == server.body.subdata(in: 4032..<4096))
    }

    /// The contract every source keeps: fewer bytes only at the end, never more. A parser
    /// that wants a short read to be an error asks through `readExactly`.
    @Test func aReadPastTheEndIsShortRatherThanRefused() async throws {
        let source = try await opened(FakeServer(bytes: 4096))
        #expect(try await source.read(offset: 4080, count: 64).count == 16)
        #expect(try await source.read(offset: 4096, count: 64).isEmpty)
        #expect(try await source.read(offset: 0, count: 0).isEmpty)
    }

    @Test func aReadBeforeTheStartIsOutOfBounds() async throws {
        let source = try await opened(FakeServer(bytes: 4096))
        await #expect(throws: SourceError.self) {
            try await source.read(offset: -1, count: 16)
        }
    }

    @Test func readExactlyRefusesWhatReadWouldClamp() async throws {
        let source = try await opened(FakeServer(bytes: 4096))
        await #expect(throws: SourceError.self) {
            try await source.readExactly(offset: 4080, count: 64)
        }
    }

    // MARK: Servers that answer wrongly

    /// A correct status, correct headers, and the bytes of some other window.
    ///
    /// **This layer cannot catch it, and pretending otherwise would be the more dangerous
    /// mistake.** HTTP carries no identity for the bytes it delivers: a body that fills its
    /// `Content-Range` is indistinguishable from the right one. What catches it is the
    /// container — a ZIP is signatures, offsets that have to agree with each other, and a
    /// CRC per entry — which is a second reason ADR-0008 was right to make the reader ours.
    /// The test below is the one that matters; this one records what the transport does
    /// *not* promise, so nobody builds on a guarantee that was never made.
    @Test func aWellFormed206WithTheWrongBytesPassesTheTransportUnnoticed() async throws {
        let server = FakeServer(bytes: 4096, lie: .offset)
        let source = HttpSource(url: address, length: 4096, transport: server)
        let read = try await source.read(offset: 1000, count: 16)
        #expect(read.count == 16)
        #expect(read != server.body.subdata(in: 1000..<1016))
    }

    /// And the container is where it stops. A server shifting every answer by 64 bytes
    /// yields an archive that does not parse, rather than pages of noise.
    @Test func aServerThatShiftsEveryAnswerYieldsNoArchive() async throws {
        let bytes = try Data(contentsOf: FixtureCorpus.url("comics/natural-sort.cbz"))
        let shifted = HttpSource(
            url: address,
            length: Int64(bytes.count),
            transport: FakeServer(body: bytes, lie: .offset)
        )
        await #expect(throws: (any Error).self) {
            let archive = try await ComicArchiveOpener.open(source: shifted)
            // A container that survived the shift must at least not claim pages that are
            // not there, so reading one is part of the assertion rather than after it.
            guard let page = archive.pages.first else { return }
            _ = try await archive.data(for: page)
        }
    }

    @Test func aBodyShorterThanItPromisedIsRefused() async throws {
        let source = HttpSource(
            url: address, length: 4096, transport: FakeServer(bytes: 4096, lie: .short)
        )
        await #expect(throws: HttpSourceError.shortBody(expected: 16, got: 15)) {
            try await source.read(offset: 1000, count: 16)
        }
    }

    /// A total that moved means the file was replaced while a reader was in it. Continuing
    /// would read the new file with the old file's central directory.
    @Test func aTotalThatChangedIsADifferentPublication() async throws {
        let source = HttpSource(
            url: address, length: 4096, transport: FakeServer(bytes: 4096, lie: .total)
        )
        await #expect(throws: HttpSourceError.lengthChanged(was: 4096)) {
            try await source.read(offset: 1000, count: 16)
        }
    }

    @Test func a416AfterOpeningMeansTheFileShrank() async throws {
        let source = HttpSource(
            url: address, length: 4096, transport: FakeServer(bytes: 4096, lie: .gone)
        )
        await #expect(throws: HttpSourceError.lengthChanged(was: 4096)) {
            try await source.read(offset: 1000, count: 16)
        }
    }

    /// The dangerous shape: the status says "all of it" and the body is a fragment. A
    /// reader that trusted the status would treat sixteen bytes as the whole archive.
    @Test func a200CarryingOnlyASliceIsRefused() async throws {
        let source = HttpSource(
            url: address, length: 4096, transport: FakeServer(bytes: 4096, lie: .status)
        )
        await #expect(throws: HttpSourceError.self) {
            try await source.read(offset: 1000, count: 16)
        }
    }

    /// A proxy that woke up mid-publication and started sending everything. Wasteful, not
    /// wrong: the bytes are all there, so the window is cut out of them.
    @Test func a200CarryingTheWholeResourceIsStillReadable() async throws {
        let server = FakeServer(bytes: 4096, lie: .ignore)
        let source = HttpSource(url: address, length: 4096, transport: server)
        let read = try await source.read(offset: 1000, count: 16)
        #expect(read == server.body.subdata(in: 1000..<1016))
    }

    @Test func aRedirectMidReadIsRefusedRatherThanFollowedBlindly() async throws {
        let source = HttpSource(
            url: address, length: 4096, transport: FakeServer(bytes: 4096, lie: .moved)
        )
        await #expect(throws: HttpSourceError.self) {
            try await source.read(offset: 0, count: 16)
        }
    }

    @Test func aServerErrorMidReadIsNamedWithItsStatus() async throws {
        let source = HttpSource(
            url: address, length: 4096, transport: FakeServer(bytes: 4096, lie: .refused(503))
        )
        await #expect(throws: HttpSourceError.refused(status: 503)) {
            try await source.read(offset: 0, count: 16)
        }
    }

    // MARK: The whole point

    /// A real archive from the shared corpus, read over ranges and never downloaded.
    ///
    /// This is ADR-0008's claim, measured: the pages a reader sees are the pages the local
    /// file has, and getting to the first one costs a fraction of the archive. The fixture
    /// is the data-descriptor one on purpose — its local headers carry zeros, so a reader
    /// that trusted them over the central directory would fail here and nowhere else.
    @Test func aCorpusArchiveOpensOverRangesAndReadsTheSamePages() async throws {
        let file = FixtureCorpus.url("comics/data-descriptor.cbz")
        let bytes = try Data(contentsOf: file)
        let counted = ReadCounter(
            try await HttpSource.open(address, transport: FakeServer(body: bytes))
        )

        let streamed = try await ComicArchiveOpener.open(source: counted)
        let local = try await ComicArchiveOpener.open(fileAt: file)
        #expect(streamed.pages.map(\.path) == local.pages.map(\.path))
        #expect(!streamed.pages.isEmpty)

        guard let cover = streamed.coverPage, let same = local.coverPage else {
            Issue.record("the corpus archive has no cover page to compare")
            return
        }
        #expect(try await streamed.data(for: cover) == (try await local.data(for: same)))

        // ADR-0008's structural claim, which is about the *number* of requests rather than
        // the bytes: opening an archive and reading one page is a handful of ranged reads
        // whatever the archive weighs. The byte saving cannot be asserted here and it is
        // worth saying why — every ZIP in the corpus is under two kilobytes, so a single
        // 64 KB tail read already covers the whole file and "less than all of it" is
        // arithmetically impossible. The saving is real at 400 MB and unmeasurable at 538
        // bytes; the request count is the part that holds at both sizes.
        #expect(counted.stats.reads <= 8)
        #expect(counted.stats.reads > 0)
    }
}
