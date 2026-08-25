public import Foundation

internal import ReadiumNavigator
internal import ReadiumShared
internal import ReadiumStreamer

public import Persistence
public import StoryArcCore

/// One EPUB, open for reading.
///
/// `ebook-reader` requires reflowable EPUB 2 and 3 to render with real
/// typography, and ADR-0005 puts Readium behind that: laying out XHTML with
/// pagination, hyphenation and a stable position across a type-size change is a
/// rendering engine's job, not a weekend's work.
///
/// What is *not* Readium's job here is the library. `EpubReader` in `Formats`
/// still indexes the book — title, author, reading order, cover — with no
/// dependency and on the host, because that is all the shelf needs. This type
/// exists only from the moment someone opens one.
///
/// `@MainActor` because it is view state, and because the navigator is a
/// `UIViewController`.
@MainActor
@Observable
public final class EpubReaderModel {
    public let publication: StoryArcCore.Publication

    /// Set when the book could not be opened at all.
    public private(set) var failure: String?

    /// How far through the whole publication, 0…1.
    ///
    /// `ebook-reader`: progress is a percentage, and "the app never presents a
    /// reflowable page number as a stable identity" — a reflowable page count
    /// depends on the type size, so there is no page number to present.
    public private(set) var progression: Double = 0

    /// The chapter the reader is in, for the chrome to name.
    public private(set) var chapterTitle: String?

    /// The navigator, once the book is open. `nil` while it is loading.
    private(set) var navigator: EPUBNavigatorViewController?

    private let url: URL
    private let progress: ProgressStore?
    private var locator: Locator?
    /// The reading order's hrefs, for the progress fallback below.
    private var readingOrder: [String] = []

    /// The navigator's delegate, held separately.
    ///
    /// Readium's delegate protocols come from a module this package imports
    /// internally, so a `public` type cannot conform to one without re-exporting
    /// Readium to everything above. A small internal object conforms instead, and
    /// nothing outside learns which engine is rendering the page.
    @ObservationIgnored private var observer: NavigatorObserver?

    public init(
        publication: StoryArcCore.Publication,
        url: URL,
        progress: ProgressStore? = nil
    ) {
        self.publication = publication
        self.url = url
        self.progress = progress
    }

    /// Opens the book and builds its navigator.
    ///
    /// Two steps, both Readium's: an `AssetRetriever` reaches the bytes, and a
    /// `PublicationOpener` parses them. Our own reader is not reused here — the
    /// navigator needs Readium's own `Publication`, and parsing an EPUB twice to
    /// avoid that would be worse than parsing it once each for two purposes.
    public func open() async {
        guard navigator == nil, failure == nil else { return }

        guard let fileURL = FileURL(url: url) else {
            failure = String(localized: "epub.failure.unreachable", bundle: .module)
            return
        }

        let assetRetriever = AssetRetriever(httpClient: DefaultHTTPClient())
        let opener = PublicationOpener(
            parser: DefaultPublicationParser(
                httpClient: DefaultHTTPClient(),
                assetRetriever: assetRetriever,
                pdfFactory: DefaultPDFDocumentFactory()
            )
        )

        switch await assetRetriever.retrieve(url: fileURL) {
        case let .success(asset):
            switch await opener.open(asset: asset, allowUserInteraction: false) {
            case let .success(opened):
                await start(opened)
            case .failure:
                failure = String(localized: "epub.failure.unreadable", bundle: .module)
            }
        case .failure:
            failure = String(localized: "epub.failure.unreachable", bundle: .module)
        }
    }

    private func start(_ opened: ReadiumShared.Publication) async {
        // A recorded position wins over the beginning. `reading-progress` is about
        // picking up where you left off, and a book you are halfway through should
        // not reopen at its title page.
        let resumed = await recordedLocator()

        do {
            let navigator = try EPUBNavigatorViewController(
                publication: opened,
                initialLocation: resumed
            )
            let observer = NavigatorObserver(model: self)
            self.observer = observer
            navigator.delegate = observer
            self.navigator = navigator
            locator = resumed
            readingOrder = opened.readingOrder.map(\.href)
            progression = resumed.map(totalProgression(of:)) ?? 0
        } catch {
            failure = String(localized: "epub.failure.unreadable", bundle: .module)
        }
    }

    /// The stored position, turned back into a Readium `Locator`.
    ///
    /// The locator is stored as its own JSON rather than as a page number:
    /// `ebook-reader` requires the position to survive a type-size change, and a
    /// page number cannot. The progression is stored beside it so the library can
    /// draw a bar without parsing anything.
    private func recordedLocator() async -> Locator? {
        guard let record = try? await progress?.progress(for: publication.identity),
              case let .reflowable(_, json) = record.position,
              !json.isEmpty,
              let value = try? JSONValue(jsonString: json, warnings: nil)
        else { return nil }
        return try? Locator(json: value, warnings: nil)
    }

    /// How far through the whole book, 0…1.
    ///
    /// Readium fills in `totalProgression` only once it has computed a positions
    /// list, which it does lazily and not at all for some publications. Without it
    /// the reader would sit at "0% read" for a whole book, which is worse than an
    /// approximation — so the fallback places the current resource in the reading
    /// order and adds how far through that resource the reader is.
    ///
    /// `ebook-reader` allows this: what it forbids is presenting a reflowable
    /// *page number* as a stable identity. A percentage is the unit it asks for.
    private func totalProgression(of locator: Locator) -> Double {
        if let total = locator.locations.totalProgression { return total }
        guard !readingOrder.isEmpty,
              let index = readingOrder.firstIndex(of: locator.href.string)
        else { return 0 }
        let within = locator.locations.progression ?? 0
        return min(1, max(0, (Double(index) + within) / Double(readingOrder.count)))
    }

    /// Moves on a tap or a key, for the chrome to drive.
    public func goForward() async {
        _ = await navigator?.goForward(options: NavigatorGoOptions(animated: true))
    }

    public func goBackward() async {
        _ = await navigator?.goBackward(options: NavigatorGoOptions(animated: true))
    }

    /// Writes the position down.
    ///
    /// Every move, not on leaving: ADR-0006 makes the local store authoritative,
    /// and a reader that only saves on a clean exit loses the evening when the app
    /// is killed in the background.
    private func record(_ locator: Locator) async {
        guard let progress else { return }
        let json = (try? locator.jsonString()) ?? ""
        let total = totalProgression(of: locator)
        try? await progress.save(
            ReadingProgress(
                identity: publication.identity,
                position: .reflowable(progression: total, locator: json),
                // A book is finished at its end, and "the end" of a reflowable
                // book is the last of its content rather than a page number.
                isFinished: total >= 0.999,
                updatedAt: Date()
            )
        )
    }
}

extension EpubReaderModel {
    /// Called by the observer when the reader moves.
    fileprivate func locationChanged(to locator: Locator) async {
        self.locator = locator
        progression = totalProgression(of: locator)
        chapterTitle = locator.title
        await record(locator)
    }
}

@MainActor
private final class NavigatorObserver: EPUBNavigatorDelegate {
    private weak var model: EpubReaderModel?

    init(model: EpubReaderModel) {
        self.model = model
    }

    func navigator(_ navigator: any Navigator, locationDidChange locator: Locator) {
        Task { await model?.locationChanged(to: locator) }
    }

    /// Readium reports a rendering failure here. It is deliberately not turned
    /// into `failure` on the model: the book is open and readable, and replacing
    /// the page with an error because one resource misbehaved would lose the
    /// reader's place over something they may never notice.
    func navigator(_ navigator: any Navigator, presentError error: NavigatorError) {}
}
