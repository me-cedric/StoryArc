import XCTest

/// The shelf, drawn from a live share whose file names lie.
///
/// D28 / task 14.13. `SmbContributor` builds a share row from its file name, so the shelf
/// used to state the extension's claim about the format and an optimistic streaming state for
/// every row. This walk photographs the shelf against a share holding four files chosen so
/// that the two answers disagree:
///
/// | File on the share | What the name claims | What its headers say |
/// | --- | --- | --- |
/// | `Tidal Reach 04.cbr` | a RAR comic | a ZIP comic, three pages |
/// | `Salt and Iron 02.cbr` | a RAR comic that streams | a solid RAR4, which never opens |
/// | `Harbour Lights 03.cbr` | a RAR comic | a stored RAR5, three pages |
/// | `Quiet Machines 02.cbz` | a ZIP comic | a ZIP comic, agreeing |
///
/// The last row is **the control**: it is the one file whose name was telling the truth, so a
/// frame where every row changed would be a frame of something else going on.
///
/// The share is `scripts/smb-server.sh`'s own fixture server. A simulator shares the Mac's
/// network stack, so `127.0.0.1` is the Mac — the same line `seed-simulator-sources.mjs`
/// explains, where Android needs `10.0.2.2` instead.
@MainActor
final class ShareRowWalkTests: XCTestCase {

    /// One registered share, as `JSONEncoder` writes `StoredRegistry` — the shape
    /// `SweepLibrary` already seeds. No credential reference, so the source connects as a
    /// guest and needs nothing in the keychain.
    private static let fixtureShare = """
    {"sources":[{"id":"4B1D6E07-9A52-4C33-8F10-5D7E2A9C4B68","displayName":"Fixture NAS",\
    "kind":"networkShare","locator":"smb://127.0.0.1:4445/Comics"}],"tombstones":[]}
    """

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// The shelf once every share row has been catalogued from its own headers.
    ///
    /// `issues` grouping rather than `series`: a cell standing for a run is named for the run
    /// and captioned with its count, and what this frame is about is what one *file* turned
    /// out to be.
    func testCaptureShareRowsCatalogued() throws {
        let app = sweepLaunch(sources: Self.fixtureShare, grouping: "issues")
        try showTheShelf(in: app)
        try narrowToTheShare(in: app)
        // The walk is a network read and the cataloguing is another one per row, both of
        // which start when the cell appears. Long enough for four rows over a loopback share.
        hold(8)
        shutter(app, named: "share-rows-catalogued")
    }

    /// The same shelf at the largest accessibility text size, where a refusal has least room.
    ///
    /// The refusal is a caption under a cover, so it is the sentence on this screen most
    /// likely to be cut off. A frame at the largest text size is what says whether a reader
    /// who needs that size still learns why the publication will not open.
    func testCaptureShareRowsCataloguedAtLargestText() throws {
        let app = sweepLaunch(
            contentSize: "UICTContentSizeCategoryAccessibilityXXXL",
            sources: Self.fixtureShare,
            grouping: "issues"
        )
        try showTheShelf(in: app)
        try narrowToTheShare(in: app)
        hold(8)
        // One row fills the screen at this size, and the refused one sorts third. Scrolled
        // to it, because a frame of the two rows above it says nothing about the sentence
        // this walk exists to photograph.
        app.swipeUp()
        app.swipeUp()
        hold(1.5)
        shutter(app, named: "share-rows-catalogued-ax5")
    }

    /// Tasks 14.14 and 14.15: a reflowable EPUB on the share opens from the share, and the
    /// frame shows its first page. Nothing is offered first, and nothing is downloaded.
    func testCaptureShareEpubStreams() throws {
        try openFromTheShare("Harbour Lights 01", settled: "ios-share-epub-read")
    }

    /// Task 14.14: a stored RAR5 comic on the share opens page by page from the share.
    func testCaptureShareCbrStreams() throws {
        try openFromTheShare("Stored Five", settled: "ios-share-cbr-read")
    }

    /// Task 14.15: a PDF on the share is fetched whole and then read with PDFKit. The frame
    /// after the open is the PDF's first page.
    func testCaptureSharePdfFetched() throws {
        try openFromTheShare("Field Notes", settled: "ios-share-pdf-read")
    }

    /// Task 14.14: a solid RAR5 is still offered as a download, with its size.
    func testCaptureShareSolidRarOffered() throws {
        let app = sweepLaunch(sources: Self.fixtureShare, grouping: "issues")
        try showTheShelf(in: app)
        try narrowToTheShare(in: app)
        hold(6)
        try openPage(of: "Solid Five", in: app)
        shutter(app, named: "ios-share-solid-page")
        let read = try XCTUnwrap(
            app.buttons.matching(opensAPublication).allElementsBoundByIndex.first(where: \.isHittable),
            "The page of the solid RAR5 offers no action."
        )
        read.tap()
        hold(3)
        shutter(app, named: "ios-share-solid-offer")
    }

    private func openFromTheShare(_ title: String, settled name: String) throws {
        let app = sweepLaunch(sources: Self.fixtureShare, grouping: "issues")
        try showTheShelf(in: app)
        try narrowToTheShare(in: app)
        hold(6)
        try openPage(of: title, in: app)
        shutter(app, named: name.replacingOccurrences(of: "-read", with: "-page"))
        let read = try XCTUnwrap(
            app.buttons.matching(opensAPublication).allElementsBoundByIndex.first(where: \.isHittable),
            "The page of \(title) offers no action."
        )
        read.tap()
        hold(6)
        shutter(app, named: name)
    }

    private func openPage(of title: String, in app: XCUIApplication) throws {
        let wanted = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title))
        var found: XCUIElement?
        for _ in 0..<6 where found == nil {
            found = wanted.allElementsBoundByIndex.first(where: \.isHittable)
            if found == nil { app.swipeUp() }
        }
        try XCTUnwrap(found, "The share shelf shows no cover for \(title). Buttons: "
            + "\(app.buttons.allElementsBoundByIndex.prefix(30).map(\.label))").tap()
        hold(2)
    }

    /// Hides the device's own corpus, so the frame holds the share's four rows and nothing
    /// else. `SweepLibrary.testCaptureNarrowedToNothing` reaches the same control the same way.
    private func narrowToTheShare(in app: XCUIApplication) throws {
        try openFilterMenu(in: app)
        try XCTUnwrap(
            hittable("Which library", in: app),
            "The Filter menu offers no library group."
        ).tap()
        guard let source = hittable("Fixture NAS", in: app, timeout: 5) else {
            throw XCTSkip(
                "This device lists no fixture share. Is scripts/smb-server.sh running? Rows: "
                    + "\(app.buttons.allElementsBoundByIndex.map(\.label))"
            )
        }
        source.tap()
        if let done = hittable("Done", in: app, timeout: 2) { done.tap() }
    }
}
