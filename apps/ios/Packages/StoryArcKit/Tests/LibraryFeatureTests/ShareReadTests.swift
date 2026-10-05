import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// What the publication page does about a row whose bytes are on a share.
///
/// Task 5.13. ``SmbContributor`` files a share row under the share's own `smb://` address, and
/// the page then asked the filesystem about it: `FileManager.fileExists` said no, the page
/// offered nothing at all, and the one row the shelf had drawn from the share could not be
/// opened or fetched from the screen the app puts between the shelf and the reader.
///
/// ``ShareOpeningTests`` pins the rule for the share browser's own tap. This pins the same rule
/// reached from the library, plus the one answer the browser gives before it: `network-share`'s
/// *Metered connection*, which asks for confirmation "before streaming or downloading".
/// Android asserts the same cases in `ShareReadTest.kt`.
@MainActor
@Suite("A share row on the publication page is judged before it is opened")
struct ShareReadTests {

    private static let share = URL(string: "smb://nas/comics/Ashfall.cbz")
        ?? URL(fileURLWithPath: "/Ashfall.cbz")

    private func row(
        format: PublicationFormat = .cbz,
        streaming: StreamingCapability = .streams,
        fileSize: Int64? = 400_000_000
    ) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: Self.share.absoluteString),
            format: format,
            displayTitle: "Ashfall",
            origin: .inferred,
            streaming: streaming,
            fileSize: fileSize
        )
    }

    private func step(
        _ publication: Publication,
        isCareful: Bool = false,
        hasConfirmedMetered: Bool = false
    ) async -> ShareRead.Ask? {
        await ShareRead.step(
            publication,
            at: Self.share,
            isCareful: isCareful,
            hasConfirmedMetered: hasConfirmedMetered
        )
    }

    // MARK: - Which addresses are a share at all

    @Test("A share address is told from a file by its scheme")
    func theSchemeDecides() {
        #expect(ShareRead.isShare(Self.share))
        #expect(!ShareRead.isShare(URL(fileURLWithPath: "/comics/Ashfall.cbz")))
        #expect(
            !ShareRead.isShare(URL(string: "https://nas/comics/Ashfall.cbz") ?? Self.share),
            "An acquisition URL is the download queue's, not a share's."
        )
    }

    // MARK: - The metered connection

    @Test("A careful link is confirmed before anything is read")
    func aCarefulLinkIsConfirmedFirst() async {
        // The defect this half closes: the page streamed from the share with no question
        // asked, while the share browser asked for the identical file.
        #expect(await step(row(), isCareful: true) == .metered)
    }

    @Test("A confirmed careful link goes on to the offer")
    func aConfirmedLinkIsNotAskedTwice() async {
        #expect(await step(row(), isCareful: true, hasConfirmedMetered: true) == nil)
    }

    @Test("An unmetered link is never confirmed")
    func anUnmeteredLinkOpens() async {
        #expect(await step(row()) == nil)
    }

    // MARK: - What the format owes

    @Test("A comic that streams opens where it lies")
    func aStreamableRowOpens() async {
        #expect(await step(row()) == nil)
    }

    @Test("A format that needs a local file is offered with its stated size")
    func aLocalOnlyFormatIsOffered() async {
        // `publication-formats`: the app "says the format has to be downloaded before it can
        // be read, states the size, and offers to download it". A PDF opened at an `smb://`
        // address would be handed to PDFKit as a path that is not one.
        #expect(await step(row(format: .pdf)) == .download(bytes: 400_000_000))
    }

    @Test("A share that stated no length is offered with no size rather than nought")
    func anUnstatedLengthIsAnAbsence() async {
        #expect(await step(row(format: .pdf, fileSize: nil)) == .download(bytes: nil))
    }

    @Test("A container no decoder opens is refused rather than fetched")
    func aRefusedRowIsSaid() async {
        // A CB7 share row carries `refused` from its name alone (`SmbContributor`), so the
        // page says so instead of offering a transfer that would change nothing.
        let ask = await step(row(format: .cb7, streaming: .refused))

        #expect(ask?.sentence != nil, "A refused row should be named, not opened or offered.")
    }

    // MARK: - The wiring the rule cannot reach

    @Test("The page sends a share row through the rule rather than opening it")
    func thePageDelegates() {
        let page = LibraryFeatureSource.code(of: "Sources/LibraryFeature/PublicationDetailView.swift")

        #expect(
            page.contains("ShareRead.step("),
            """
            PublicationDetailView opens a share row itself again. The confirmation and the \
            offer belong to ShareRead.step, which this suite drives.
            """
        )
        #expect(
            page.contains("?? shareAddress"),
            """
            The page no longer falls back to the share's own address, so a share row has no \
            address at all and the primary action disappears — task 5.13's own defect.
            """
        )
    }

    @Test("A bulk keep copies a share member in chunks rather than skipping it")
    func theKeepTakesTheChunkedRoute() {
        let keep = LibraryFeatureSource.code(of: "Sources/LibraryFeature/KeepOffline.swift")

        #expect(
            keep.contains("ShareRead.isShare(url)"),
            "keepOffline hands a share address to FileManager.copyItem again, which skips it."
        )
        #expect(
            keep.contains("ChunkedCopy.copy(source, to: destination)"),
            """
            The share route should copy through ChunkedCopy, as the single keep-for-offline \
            action does — task 7.7's decision.
            """
        )
    }
}
