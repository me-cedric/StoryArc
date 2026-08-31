import Testing

@testable import StoryArcCore

/// `publication-formats`' two remote scenarios of *Streaming capability per format*,
/// asserted case for case. Android's `StreamingOfferTest` asserts the same cases.
///
/// The pair is the point. A publication that cannot be streamed owes the reader a sentence,
/// a size and an offer *before* anything is transferred; the same publication once it is on
/// the device owes them nothing at all, "because the constraint was never about the format
/// being readable". One rule has to give both answers, or the second turns into a notice on
/// every solid comic a reader has already downloaded.
@Suite("What cannot be streamed is offered as a download, and once downloaded is just a book")
struct StreamingOfferTests {

    @Test("A solid archive on a share is offered as a download, with its size")
    func solidRemoteIsOffered() {
        // The scenario: "the app says the format has to be downloaded before it can be read,
        // states the size, and offers to download it".
        #expect(
            StreamingOffer.of(
                streaming: .downloadOnly, isLocal: false, readsWhereItLies: true, bytes: 1_050
            ) == .download(bytes: 1_050)
        )
    }

    @Test("It is never handed to a reader to stream badly")
    func solidRemoteIsNotStreamed() {
        // The other half of the same scenario: "it does not begin streaming badly and leave
        // the user watching a stalled page". `readsWhereItLies` is true here — the container
        // would happily supply page one — and the answer is still not `open`.
        let offer = StreamingOffer.of(
            streaming: .downloadOnly, isLocal: false, readsWhereItLies: true, bytes: nil
        )
        #expect(offer != .open)
    }

    @Test("A download-only publication already on the device opens with no notice")
    func solidLocalOpens() {
        // "A solid archive already downloaded ... opens directly with no notice." `open` is
        // that: nothing to say, nothing to confirm, no size to state.
        #expect(
            StreamingOffer.of(
                streaming: .downloadOnly, isLocal: true, readsWhereItLies: false, bytes: 1_050
            ) == .open
        )
    }

    @Test("A refusal is a refusal once the bytes are here, and no transfer is offered")
    func refusedLocalIsRefused() {
        // Solid RAR4. "It does not hold for solid RAR4, which is refused whether local or
        // remote" — and a download that changes nothing must not be offered.
        #expect(
            StreamingOffer.of(
                streaming: .refused, isLocal: true, readsWhereItLies: false, bytes: 400
            ) == .refuse
        )
    }

    @Test("A remote record marked refused is fetched rather than declined")
    func refusedRemoteIsFetched() {
        // `PublicationIndexer.index(source:...)` marks a remote PDF, EPUB or CBR `refused`
        // to mean "its pages cannot be reached from here". Believing that as a refusal
        // would decline to fetch every comic in a RAR on every share.
        #expect(
            StreamingOffer.of(
                streaming: .refused, isLocal: false, readsWhereItLies: false, bytes: 9_000
            ) == .download(bytes: 9_000)
        )
    }

    @Test("A decoder that cannot work from a source is a download whatever the container said")
    func needsAFileIsADownload() {
        #expect(
            StreamingOffer.of(
                streaming: .streams, isLocal: false, readsWhereItLies: false, bytes: 42
            ) == .download(bytes: 42)
        )
    }

    @Test("A streamable publication on a share is read where it lies")
    func streamableStaysRemote() {
        // `network-share`'s whole promise, and this rule must not cost it: a CBZ on a NAS
        // still opens from its headers.
        #expect(
            StreamingOffer.of(
                streaming: .streams, isLocal: false, readsWhereItLies: true, bytes: 400_000_000
            ) == .open
        )
    }

    @Test("An unstated length is offered as an absence rather than as a zero")
    func unstatedLength() {
        // `offline-downloads` is explicit that a fabricated size is worse than an honest
        // blank, and a zero would read as a free download.
        #expect(
            StreamingOffer.of(
                streaming: .downloadOnly, isLocal: false, readsWhereItLies: false, bytes: nil
            ) == .download(bytes: nil)
        )
    }
}
