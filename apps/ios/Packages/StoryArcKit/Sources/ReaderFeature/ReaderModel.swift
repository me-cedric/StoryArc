public import CoreGraphics
public import Foundation

public import SwiftUI

public import Formats
public import Persistence
public import StoryArcCore

/// One publication, open for reading.
///
/// Holds the page list, the current position, and a small window of decoded
/// pages. `comic-reader` requires a turn to be immediate, which means the next
/// page has to be decoded before it is asked for — so this keeps neighbours warm
/// and drops what has scrolled away.
///
/// `@MainActor` because it is view state. Decoding happens off it.
@MainActor
@Observable
public final class ReaderModel {
    public let publication: Publication
    public private(set) var pages: [PageEntry] = []
    public private(set) var currentIndex = 0
    /// Set when the publication could not be opened at all.
    public private(set) var failure: String?

    /// How many pages to keep decoded, and in which direction.
    ///
    /// `comic-reader`: "at least the next three and previous one page are decoded
    /// and held ready". Asymmetric because reading is: three ahead covers a fast
    /// run of turns, one behind covers the glance back, and five pages of a
    /// 2000×3000 corpus is a bound `publication-formats` is happy with.
    private let lookAhead = 3
    private let lookBehind = 1

    private var decoded: [Int: CGImage] = [:]

    // Internal, not private, for both of these: the thumbnail half of this type lives in
    // another file, and `private` is file-scoped.

    /// Small versions of pages, for the thumbnail strip.
    ///
    /// Kept apart from `decoded` because the two have different lifetimes: a page
    /// leaves the reading window as soon as it is three turns away, and a thumbnail
    /// is wanted for as long as the strip is open.
    var thumbnails: [Int: CGImage] = [:]

    /// What this publication's cover brings to its own screens, or `nil` when it
    /// brings none. Derived once, when the publication opens; the reason it is
    /// derived from the cover's *thumbnail* is in ``deriveCoverColours()``.
    public internal(set) var coverColours: CoverColours?

    var archive: (any ComicArchiveReading)?
    /// Set instead of [archive] for a PDF, whose pages are drawn rather than
    /// stored. `ebook-reader` requires a several-hundred-megabyte PDF to render
    /// pages as they are needed, so nothing is rasterised until it is asked for.
    private var pdf: PdfPageRenderer?
    private let url: URL
    private var maxPixelSize = 2048
    private let progress: ProgressStore?

    /// - Parameters:
    ///   - preferences: where the reading mode is remembered. `nil` in a test.
    ///     `comic-reader`'s mode persistence is word for word `reading-themes`' theme
    ///     persistence — per series, with a global default, and comics independent of
    ///     reflowable — so it is the same store.
    ///   - canCurl: whether this device can render the curl. iOS 26 is the floor
    ///     (ADR-0003) and SwiftUI's shader API predates it, so there is no capability
    ///     to gate on — unlike Android, where `RuntimeShader` arrives at API 33.
    ///
    ///     The frame-rate half of `page-transitions`' requirement is a *runtime*
    ///     question rather than a build-time one: the same shader is fast on one device
    ///     and not on another. A check with no device known to fail it would be
    ///     speculative, so the parameter exists to be passed `false` when one is found.
    public init(
        publication: Publication,
        url: URL,
        progress: ProgressStore? = nil,
        preferences: ReaderPreferences? = nil,
        canCurl: Bool = true
    ) {
        self.publication = publication
        self.url = url
        self.progress = progress
        self.preferences = preferences
        self.canCurl = canCurl
        self.shelf = ShelfMemory.shelf(series: publication.series, identity: publication.id)
        self.settings = preferences?.themes().theme(for: .fixedLayout, shelf: shelf)
            ?? ShelfSettings()
    }

    /// What this shelf is read with.
    public private(set) var settings: ShelfSettings

    @ObservationIgnored private let preferences: ReaderPreferences?
    @ObservationIgnored private let canCurl: Bool
    @ObservationIgnored private let shelf: String

    /// Height over width of the first decoded page, or 0 while nothing is decoded.
    @ObservationIgnored private var firstPageRatio = 0.0

    /// Which transition rows to offer, which of them cannot run, and what runs instead.
    ///
    /// - Parameter reduceMotion: read from the environment by the view, because that is
    ///   where a SwiftUI accessibility setting lives and where a change to it arrives.
    ///   `page-transitions` requires turning it off mid-session to restore the chosen
    ///   mode without reopening the reader, which is exactly what an environment read
    ///   gives for free.
    public func transitions(reduceMotion: Bool) -> TransitionChoices {
        TransitionChoices(
            chosen: settings.transition,
            axis: settings.scrollAxis ?? impliedAxis,
            reduceMotion: reduceMotion,
            canCurl: canCurl
        )
    }

    /// The axis the publication implies, until the reader overrides it.
    ///
    /// Measured from the first decoded page rather than declared: a webtoon rarely says
    /// it is one, and `comic-reader` recognises it by pages "materially taller than
    /// they are wide". First rather than tallest, because waiting for the tallest means
    /// waiting for the whole publication.
    private var impliedAxis: ScrollAxis {
        ScrollAxis.implied(
            isReflowable: false,
            isTall: firstPageRatio >= ScrollAxis.tallnessThreshold,
            // A comic's own reading direction is across the page, which is what makes
            // horizontal the implied axis for anything that is not a strip.
            declaresHorizontal: true
        )
    }

    /// The colour behind the page, and only behind it.
    ///
    /// `reading-themes`: a custom background "applies to the area around the page and not
    /// to the page itself, because tinting artwork is not a reading preference". So this is
    /// the matte, the artwork is drawn over it untouched, and a *preset* does not reach
    /// here at all — a preset is a typographic theme and its paper colour means nothing
    /// behind a page of artwork. Only a colour the reader chose explicitly applies.
    ///
    /// Black otherwise, which is what a comic is read against.
    public var matte: Color {
        guard let hex = settings.theme.custom?.background else { return .black }
        return Color(readerHex: hex) ?? .black
    }

    /// Chooses a transition, for this shelf, from now on.
    public func choose(_ transition: PageTransition) {
        remember(settings.settingTransition(transition))
    }

    /// Overrides the scroll axis, which `page-transitions` requires to be possible.
    public func choose(_ axis: ScrollAxis) {
        remember(settings.settingScrollAxis(axis))
    }

    private func remember(_ new: ShelfSettings) {
        settings = new
        guard let preferences else { return }
        preferences.save(
            preferences.themes().remembering(new, for: .fixedLayout, shelf: shelf)
        )
    }

    /// Records a decoded page's shape, once, for the implied axis.
    func noteDecoded(_ image: CGImage) {
        guard firstPageRatio == 0, image.width > 0 else { return }
        firstPageRatio = Double(image.height) / Double(image.width)
    }

    /// The direction the reader turns pages in.
    ///
    /// From the publication, which took it from `ComicInfo` or the language. The
    /// reader never guesses it separately — a manga that opens left-to-right on
    /// one screen and right-to-left on another is worse than either.
    public var readingDirection: ReadingDirection { publication.readingDirection }

    public var currentPage: PageEntry? {
        pages.indices.contains(currentIndex) ? pages[currentIndex] : nil
    }

    /// Opens the publication and decodes the first page.
    ///
    /// Whatever happens, this leaves the reader in a state it can be got out of. A
    /// publication with no pages used to show the loading spinner for ever: the chrome
    /// timed out after four seconds and left a black screen with no close button, and the
    /// only way back to the library was to force-quit the app.
    public func open(maxPixelSize: Int) async {
        self.maxPixelSize = maxPixelSize
        if publication.format == .pdf {
            await openPDF()
            noteIfEmpty()
            return
        }
        do {
            let opened = try await ComicArchiveOpener.open(fileAt: url)
            archive = opened
            pages = opened.pages
            // Start at the designated cover when there is one. `publication-formats`
            // lets ComicInfo name a cover that is not page one, and opening on a
            // different page than the library showed would be disorienting.
            if let coverPath = publication.coverPath,
               let index = pages.firstIndex(where: { $0.path == coverPath }) {
                currentIndex = index
            }
            // A recorded position wins over the cover. `reading-progress` is about
            // picking up where you left off, and a book you are halfway through
            // should not reopen at its cover.
            if let recorded = try? await progress?.progress(for: publication.identity),
               case let .page(index, _) = recorded.position,
               pages.indices.contains(index) {
                currentIndex = index
            }
            await warm(around: currentIndex)
            await deriveCoverColours()
        } catch {
            failure = String(describing: error)
        }
        noteIfEmpty()
    }

    /// Says so when a publication opened and turned out to hold nothing.
    ///
    /// A container can be perfectly well-formed and contain no pages this app can decode —
    /// a fixed-layout EPUB of text, an archive of files that are not images. Nothing threw,
    /// so there is no error to report, and the honest answer is that there is nothing here
    /// rather than a spinner that never stops.
    private func noteIfEmpty() {
        guard failure == nil, pages.isEmpty else { return }
        failure = String(localized: "reader.empty", bundle: .module, locale: .storyArc)
    }

    /// Opens a PDF.
    ///
    /// Its own path because a PDF has no entries to list: the page list is the
    /// page *count*, and each entry exists only to give the pager something to
    /// count and to label. A recorded position still wins over page one, exactly
    /// as it does for an archive.
    private func openPDF() async {
        do {
            let reader = try PdfPageRenderer(url: url)
            pdf = reader
            pages = (0..<reader.pageCount).map { index in
                PageEntry(path: String(index + 1))
            }
            if let recorded = try? await progress?.progress(for: publication.identity),
               case let .page(index, _) = recorded.position,
               pages.indices.contains(index) {
                currentIndex = index
            }
            await warm(around: currentIndex)
            await deriveCoverColours()
        } catch {
            failure = String(describing: error)
        }
    }

    /// The decoded page at an index, if it is ready.
    public func image(at index: Int) -> CGImage? { decoded[index] }

    /// Whether a page failed to decode, as opposed to not being ready yet.
    public func isUnavailable(at index: Int) -> Bool {
        attempted.contains(index) && decoded[index] == nil
    }

    private var attempted: Set<Int> = []

    public func go(to index: Int) async {
        guard pages.indices.contains(index) else { return }
        currentIndex = index
        await warm(around: index)
        await record(index)
    }

    /// Writes the position down.
    ///
    /// Every turn, not on leaving: ADR-0006 makes the local store authoritative,
    /// and a reader that only saves on a clean exit loses the evening when the app
    /// is killed in the background — which is the normal way a phone closes an app.
    ///
    /// The last page marks the publication finished. Finished is sticky, so
    /// turning back afterwards does not unmark it.
    private func record(_ index: Int) async {
        guard let progress, !pages.isEmpty else { return }
        try? await progress.save(
            ReadingProgress(
                identity: publication.identity,
                position: .page(index: index, of: pages.count),
                isFinished: index == pages.count - 1,
                updatedAt: Date()
            )
        )
    }

    /// The next page in *reading* order, which is not always the next index.
    public func advance() async {
        await go(to: currentIndex + 1)
    }

    public func retreat() async {
        await go(to: currentIndex - 1)
    }

    /// Decodes the current page and its neighbours, and drops the rest.
    private func warm(around index: Int) async {
        let wanted = Set((index - lookBehind)...(index + lookAhead))
            .filter { pages.indices.contains($0) }
        // Dropped before decoding, so peak memory is the window and not the window
        // plus whatever was there before.
        for key in decoded.keys where !wanted.contains(key) {
            decoded.removeValue(forKey: key)
            attempted.remove(key)
        }
        // The current page first: a turn should not wait on its neighbours.
        for target in [index] + wanted.sorted(by: { abs($0 - index) < abs($1 - index) }) {
            guard decoded[target] == nil, !attempted.contains(target) else { continue }
            await decode(target)
        }
    }

    private func decode(_ index: Int) async {
        guard pages.indices.contains(index) else { return }
        attempted.insert(index)
        let size = maxPixelSize

        if let pdf {
            if let image = await pdf.image(at: index, maxPixelSize: size) {
                decoded[index] = image
                noteDecoded(image)
            } else {
                attempted.remove(index)
            }
            return
        }

        guard let archive else { return }
        let page = pages[index]
        let image = await Task.detached(priority: .userInitiated) {
            guard let data = try? await archive.data(for: page) else { return CGImage?.none }
            return try? PageDecoder.decode(data, maxPixelSize: size)
        }.value
        if let image {
            decoded[index] = image
            noteDecoded(image)
        } else {
            // Forgotten rather than remembered as tried. A page that failed because the
            // share was away must be readable once it comes back — `network-share` asks the
            // app to "resume streaming at the current page" after reconnecting, and a page
            // marked attempted for ever never gets a second chance.
            attempted.remove(index)
        }
    }
}

/// A PDF, rendered off the main actor.
///
/// `PDFDocument` is not `Sendable`, so the reader cannot be handed to a detached
/// task — Swift 6 rejects that outright, and it would be a real race rather than
/// a pedantic one. An actor owns the document instead: it is created inside the
/// actor and never leaves it, and renders serialise, which is what PDFKit wants
/// anyway.
private actor PdfPageRenderer {
    private let reader: PdfDocumentReader

    /// Page count, read once. Cheap, and it saves an `await` per pager layout.
    nonisolated let pageCount: Int

    init(url: URL) throws {
        let reader = try PdfDocumentReader(url: url)
        self.reader = reader
        self.pageCount = reader.pageCount
    }

    /// One page, rasterised at the size it will be drawn.
    ///
    /// `nil` rather than a throw: the reader shows a named "page unavailable"
    /// placeholder for a page it cannot produce, and one bad page in a PDF should
    /// not close the whole document.
    func image(at index: Int, maxPixelSize: Int) -> CGImage? {
        try? reader.render(pageAt: index, maxPixelSize: maxPixelSize)
    }
}
