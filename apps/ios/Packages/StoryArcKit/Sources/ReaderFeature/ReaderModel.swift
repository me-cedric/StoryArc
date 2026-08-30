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

    /// Pages that take the width of two.
    ///
    /// `comic-reader` shows such a page alone rather than pairing it with a neighbour.
    /// Two sources, answering different halves of the same question: `ComicInfo`
    /// *declares* spreads and is believed outright, and a page that decoded wider than
    /// it is tall is one whether the file says so or not — most CBZs carry no metadata
    /// at all, so a declaration alone would find nothing in the common case.
    ///
    /// Grows as pages decode, which means a landscape layout can regroup itself a few
    /// pages ahead of the reader. That is what "detected" means; the reader keeps its
    /// *page* across the regrouping rather than its slot, so nothing moves under it.
    public private(set) var wideIndices: Set<Int> = []

    /// How many pages to keep decoded, and in which direction.
    ///
    /// Starts at the window `comic-reader` asks for and narrows when the system says
    /// memory is short — see ``noteMemoryPressure(_:)``. A `var` for that reason: the
    /// spec's floor is a floor for normal conditions, not for the moment the system is
    /// choosing a process to end.
    var prefetch = PrefetchWindow.full

    var decoded: [Int: CGImage] = [:]

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
    var pdf: PdfPageRenderer?
    private let url: URL
    var maxPixelSize = 2048
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

    /// Reads this shelf the other way round, from now on.
    public func choose(_ direction: ReadingDirection) {
        remember(settings.settingReadingDirection(direction))
    }

    /// Shifts the spread pairing by one, or puts it back, for this shelf from now on.
    ///
    /// `comic-reader` asks for the offset "for publications whose cover throws the
    /// pairing off", and that is a fact about the series rather than about the reader —
    /// so it is remembered where the reading mode is, and issue two opens paired right.
    public func chooseSpreadOffset(_ isOffset: Bool) {
        remember(settings.settingSpreadOffset(isOffset))
    }

    /// Shows or hides the line between pages in a continuous scroll.
    public func choosePageSeparator(_ isShown: Bool) {
        remember(settings.settingPageSeparator(isShown))
    }

    private func remember(_ new: ShelfSettings) {
        settings = new
        guard let preferences else { return }
        preferences.save(
            preferences.themes().remembering(new, for: .fixedLayout, shelf: shelf)
        )
    }

    /// Records what a decoded page's shape tells us: the implied axis, and whether the
    /// page is a spread.
    ///
    /// The axis is taken from the first page only — a webtoon rarely declares itself and
    /// waiting for the tallest page means waiting for the whole publication. Wideness is
    /// per page, because that is the question being asked about each one.
    func noteDecoded(_ image: CGImage, at index: Int) {
        if firstPageRatio == 0, image.width > 0 {
            firstPageRatio = Double(image.height) / Double(image.width)
        }
        // Wider than tall, with no tolerance to tune: a portrait page scanned with a
        // slight skew is still portrait, and a spread is half again as wide as a page.
        if image.width > image.height { wideIndices.insert(index) }
    }

    /// The direction the reader turns pages in.
    ///
    /// The publication's own — from `ComicInfo` or the language — until the reader
    /// overrules it. `comic-reader` lets them, because metadata is often wrong about
    /// this and a manga tagged left-to-right is unreadable; the override is "remembered
    /// for the series", so it is kept where every other per-series decision is kept
    /// rather than against this one file.
    public var readingDirection: ReadingDirection {
        settings.readingDirection ?? publication.readingDirection
    }

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
            wideIndices = Set(opened.doublePageIndices)
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
            //
            // Unless it is finished, which the same requirement singles out: reopening a
            // finished publication "starts at the beginning while retaining the finished
            // record". Dropping the override is the whole of it — the record is untouched,
            // and the beginning is where `currentIndex` already is.
            if let recorded = try? await progress?.progress(for: publication.identity),
               !recorded.isFinished,
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
            // Finished reopens at page one, exactly as an archive does.
            if let recorded = try? await progress?.progress(for: publication.identity),
               !recorded.isFinished,
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

    var attempted: Set<Int> = []

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
}
