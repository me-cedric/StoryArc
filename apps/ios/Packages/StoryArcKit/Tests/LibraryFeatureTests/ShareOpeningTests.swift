import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// What the share browser does about one publication, driven rather than read as text.
///
/// ``SmbTransferWiringTests`` reads the browser's source, and that is all a suite with no
/// simulator can do to a SwiftUI view. It is also not enough, and the review of this change
/// proved it: replacing the judgement in `transfer(_:)` with `_ = offer; onOpen(publication,
/// local)` left `StreamingOffer.of(` before `onOpen(` in the text and passed all 1389 tests —
/// so the second defect this change exists to fix survived with a green suite. The decisions
/// moved into `ShareOpening` so that this suite can call them with a publication of its
/// choosing and watch which callback fires.
///
/// ``StreamingOfferTests`` pins the *rule*, in `StoryArcCore`. This pins what the browser feeds
/// it and what it does with the answer. Android asserts the same cases in `ShareOpeningTest.kt`.
@MainActor
@Suite("What a share hands back is judged before the reader is sent to it")
struct ShareOpeningTests {

    /// What a callback did, so a test can assert on one thing rather than on four flags.
    private final class Answers {
        var opened: (Publication, URL)?
        var offered: Int64?
        var offerMade = false
        var said: LocalizedStringResource?
    }

    private static let remote = URL(string: "smb://nas/comics/Solid.cbr")
        ?? URL(fileURLWithPath: "/Solid.cbr")
    private static let local = URL(fileURLWithPath: "/tmp/Smb/Solid.cbr")

    private func publication(
        format: PublicationFormat = .cbr,
        streaming: StreamingCapability = .streams
    ) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: Self.remote.absoluteString),
            format: format,
            displayTitle: "Solid",
            origin: .inferred,
            streaming: streaming
        )
    }

    private func openingFromShare(
        _ publication: Publication,
        length: Int64 = 400_000_000
    ) async -> Answers {
        let answers = Answers()
        await ShareOpening.offerOrOpen(
            index: { (publication, Self.remote) },
            length: length,
            onOpen: { found, url in answers.opened = (found, url) },
            onOffer: { bytes in answers.offerMade = true; answers.offered = bytes },
            onSay: { said in answers.said = said }
        )
        return answers
    }

    private func arrivalFromShare(_ publication: Publication) async -> Answers {
        let answers = Answers()
        await ShareOpening.openWhatArrived(
            fetch: { (publication, Self.local) },
            onOpen: { found, url in answers.opened = (found, url) },
            onSay: { said in answers.said = said }
        )
        return answers
    }

    // MARK: - What arrived from a completed transfer

    @Test("A solid RAR4 that has finished arriving is refused rather than opened")
    func refusedArrivalIsNotOpened() async {
        // The defect, exactly. A solid archive indexes as `refused` only once its bytes are
        // local — libarchive reads FHD_SOLID through a path — so this is the first moment the
        // app can know, and the reader has already paid for the whole file. Opening it sends
        // them to a reader that cannot render page one.
        let answers = await arrivalFromShare(publication(streaming: .refused))

        #expect(
            answers.opened == nil,
            """
            The publication was opened after the transfer even though no decoder will read \
            it. `publication-formats` asks for the refusal to be named instead.
            """
        )
        #expect(
            answers.said == ShareOpening.cannotOpen,
            "The refusal `publication-formats` asks to be named was not the sentence shown."
        )
    }

    @Test("A solid RAR5 that has finished arriving opens with no notice")
    func downloadedSolidRar5Opens() async {
        // The other half of the same rule: `downloadOnly` once local is just a book. "It opens
        // directly with no notice, because the constraint was never about the format being
        // readable."
        let answers = await arrivalFromShare(publication(streaming: .downloadOnly))

        #expect(answers.opened?.1 == Self.local)
        #expect(answers.said == nil, "A downloaded solid RAR5 got a notice.")
    }

    @Test("A transfer that failed is named rather than swallowed")
    func failedTransferIsNamed() async {
        let answers = Answers()
        await ShareOpening.openWhatArrived(
            fetch: { throw CancellationError() },
            onOpen: { found, url in answers.opened = (found, url) },
            onSay: { said in answers.said = said }
        )

        #expect(answers.said == ShareOpening.unexpected)
        #expect(answers.opened == nil)
    }

    // MARK: - What was found on the share

    @Test("A CBZ on a share is read where it lies")
    func streamableStaysRemote() async {
        // `network-share`'s whole promise: the first page of a 400 MB comic costs megabytes.
        let answers = await openingFromShare(publication(format: .cbz))

        #expect(answers.opened?.1 == Self.remote)
        #expect(!answers.offerMade, "A streamable comic was offered as a download.")
    }

    @Test("A PDF on a share is offered with the size the share stated")
    func pdfIsOfferedWithItsSize() async {
        // PDFKit wants a file, so the whole thing has to come across — and
        // `publication-formats` asks the app to state the size and offer it, not take it.
        let answers = await openingFromShare(publication(format: .pdf), length: 1_050)

        #expect(answers.offerMade, "A PDF on a share was opened rather than offered.")
        #expect(answers.offered == 1_050)
        #expect(answers.opened == nil)
    }

    @Test("An EPUB on a share is offered rather than streamed")
    func epubIsOffered() async {
        // The EPUB reader opens a file of its own. `publication-formats`' table says the format
        // streams, which is true of its index and not of this platform's reader.
        let answers = await openingFromShare(publication(format: .epub))
        #expect(answers.offerMade)
    }

    @Test("A share that states no length offers an absence rather than a zero")
    func unstatedLengthIsAnAbsence() async {
        // `offline-downloads` requires an unknown size to be stated as an absence "rather than
        // as a zero", and a directory entry's length is a non-optional `Int64` — so a zero is
        // the only shape "the server said nothing" can arrive in, and a zero in a download
        // offer reads as a free download.
        let answers = await openingFromShare(publication(format: .pdf), length: 0)

        #expect(answers.offerMade, "A publication needing a transfer was not offered at all.")
        #expect(answers.offered == nil, "A zero-length entry was offered as a size.")
    }

    @Test("An index that failed over the share is named rather than swallowed")
    func failedIndexIsNamed() async {
        let answers = Answers()
        await ShareOpening.offerOrOpen(
            index: { throw CancellationError() },
            length: 10,
            onOpen: { found, url in answers.opened = (found, url) },
            onOffer: { bytes in answers.offerMade = true; answers.offered = bytes },
            onSay: { said in answers.said = said }
        )

        #expect(answers.said == ShareOpening.unexpected)
        #expect(!answers.offerMade, "A failed index still offered a transfer.")
    }

    @Test("A solid RAR4 on a share is refused before the whole file is transferred")
    func solidRar4OnAShareIsRefused() async {
        // `RarComicArchive` detects a solid RAR4 from its headers alone, so this is no
        // longer a placeholder meaning "not checked yet" — it is the real answer, and
        // believing it here is what stops the reader paying for a transfer that changes
        // nothing.
        let answers = await openingFromShare(publication(streaming: .refused))

        #expect(
            !answers.offerMade,
            "A solid RAR4 on a share was offered a transfer instead of being refused."
        )
        #expect(answers.said == ShareOpening.cannotOpen)
    }

    // MARK: - Where a publication's own page opens it from

    /// A transfer in flight for this publication, in whatever state the case needs.
    private func transfer(_ state: Download.State) -> Download {
        var record = Download(
            id: "solid",
            sourceID: nil,
            title: "Solid",
            remote: URL(string: "http://127.0.0.1:4444/files/Solid.cbz") ?? Self.local,
            mediaType: "application/vnd.comicbook+zip"
        )
        record.state = state
        return record
    }

    @Test("A comic still arriving opens from the address the transfer is fetching")
    func aComicStillArrivingStreams() {
        let address = ShareOpening.address(
            for: publication(format: .cbz),
            local: nil,
            transfer: transfer(.running)
        )

        #expect(address?.scheme == "http", "the page offered no address to stream from")
    }

    /// The local copy wins, which is the whole of `offline-downloads`: a publication already
    /// here reads with no network at all.
    @Test("A copy on this device wins over an address, whatever the transfer says")
    func theCopyOnThisDeviceWins() {
        #expect(
            ShareOpening.address(for: publication(format: .cbz), local: Self.local, transfer: transfer(.running))
                == Self.local
        )
    }

    /// PDFKit wants a file. Offering a reader a PDF that is not there yet would open nothing.
    @Test("A format whose decoder wants a file does not stream")
    func aFormatThatWantsAFileDoesNotStream() {
        #expect(
            ShareOpening.address(for: publication(format: .pdf), local: nil, transfer: transfer(.running)) == nil
        )
    }

    /// Finished with no local copy means the file went away, and failed is a state the spec
    /// requires to be stated with a retry rather than read past. Neither is an address.
    @Test("A transfer that is over is not an address, whichever way it ended")
    func aTransferThatIsOverIsNotAnAddress() {
        for state in [Download.State.finished, .failed(reason: "gone", attempts: 1)] {
            #expect(
                ShareOpening.address(for: publication(format: .cbz), local: nil, transfer: transfer(state)) == nil,
                "a \(state) transfer was offered as somewhere to read from"
            )
        }
    }

    @Test("A publication with no copy and no transfer opens from nowhere")
    func nothingToOpen() {
        #expect(ShareOpening.address(for: publication(format: .cbz), local: nil, transfer: nil) == nil)
    }

    // MARK: - The fact the rule is fed

    @Test("Only the formats whose decoder wants a file need one")
    func theDecoderListIsTheDecoderList() {
        // `publication-formats`' capability table says CBZ, CBT, EPUB, PDF and non-solid CBR
        // all stream. What is true of the *format* is not true of this platform's decoders:
        // PDFKit wants a file, libarchive wants a path, and the EPUB reader opens one of its
        // own. Android's list is shorter, because its EPUB reader takes a source.
        #expect(
            PublicationFormat.allCases.filter(ShareOpening.needsLocalFile) == [.cbr, .epub, .pdf]
        )
    }

    // MARK: - Reading while downloading, from a catalogue entry

    @Test("A comic acquisition reads from its catalogue address")
    func comicAcquisitionReadsWhereItLies() {
        #expect(ShareOpening.catalogueReadsWhereItLies(.cbz))
    }

    @Test("A PDF or CBR acquisition does not, because the decoder wants a file")
    func fileDecodersDoNotStreamFromTheCatalogue() {
        #expect(!ShareOpening.catalogueReadsWhereItLies(.pdf))
        #expect(!ShareOpening.catalogueReadsWhereItLies(.cbr))
        #expect(!ShareOpening.catalogueReadsWhereItLies(.epub))
    }

    @Test("An audio acquisition does not stream, even though AVURLAsset is not asked")
    func audioAcquisitionDoesNotStreamFromTheCatalogue() {
        // There is no `Publication` yet to read a `StreamingCapability` off, so this has to
        // be excluded on the format alone — `AVURLAsset` wants a file regardless of what a
        // read of the container would have said.
        #expect(!ShareOpening.catalogueReadsWhereItLies(.m4b))
    }

    @Test("A media type nothing recognises does not stream")
    func unrecognisedMediaTypeDoesNotStream() {
        #expect(!ShareOpening.catalogueReadsWhereItLies(nil))
    }
}
