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

    /// Which preset is on and which axes have been moved from it.
    public private(set) var theme: ReadingTheme

    /// The typography in force: the preset's own values until an axis is moved.
    public private(set) var values: ThemeValues

    /// Reader-local screen brightness, 0…1, or `nil` for the device's own.
    ///
    /// `reading-themes`: "reader-local screen brightness, independent of the system
    /// slider", and the system brightness "is not permanently modified". `nil` means
    /// the reader has not touched it, which is different from having set it to
    /// whatever the device happens to be at — the difference matters when the
    /// reader leaves and the original has to come back.
    public var brightness: Double?

    /// The navigator, once the book is open. `nil` while it is loading.
    private(set) var navigator: EPUBNavigatorViewController?

    private let url: URL
    private let progress: ProgressStore?
    /// Where the reader's theme choices live between sessions. `nil` in a test.
    private let preferences: ReaderPreferences?
    /// The key this publication remembers its theme under.
    private let shelf: String
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

    /// - Parameter preferences: the store the theme is read from and written back
    ///   to. Passing `nil` gives a reader that forgets, which is what a test wants
    ///   and what the app had before themes persisted.
    public init(
        publication: StoryArcCore.Publication,
        url: URL,
        progress: ProgressStore? = nil,
        preferences: ReaderPreferences? = nil
    ) {
        self.publication = publication
        self.url = url
        self.progress = progress
        self.preferences = preferences
        // Its series, or itself where it has none. `reading-themes` scopes a theme to
        // the series, and a standalone book is a series of one.
        self.shelf = ThemeMemory.shelf(series: publication.series, identity: publication.id)

        // The reflowable scope. A fixed-layout EPUB never reaches this reader —
        // `ebook-reader` sends it to the comic reader, which has pages.
        let stored = preferences?.themes().theme(for: Self.scope, shelf: shelf) ?? StoredTheme()
        self.theme = stored.theme
        self.values = stored.values
    }

    /// Always reflowable. See the note in `init`.
    private static let scope = ThemeScope.reflowable

    /// Adopts a preset, discarding any deviation from the last one.
    ///
    /// `reading-themes`: tapping a preset applies "every axis the preset defines at
    /// once and the change is visible immediately in the reader behind the sheet".
    public func adopt(_ preset: ThemePreset) {
        theme = theme.adopting(preset)
        values = preset.values
        applyTheme()
    }

    /// Sets one slider axis, in one call, so the sheet can drive nine of them.
    public func set(_ axis: ThemeAxis, to value: Double) {
        change(axis, to: values.setting(axis, to: value))
    }

    /// Moves one axis, which marks the preset modified without deselecting it.
    ///
    /// The axis is passed alongside the new values so the model records *which* axis
    /// moved — the sheet needs that to offer "restore this preset", and Readium
    /// cannot tell us.
    public func change(_ axis: ThemeAxis, to values: ThemeValues) {
        guard theme.isEffective(axis) else { return }
        self.values = values
        theme = theme.deviating(on: axis)
        applyTheme()
    }

    /// Puts every axis back to the preset's own values.
    public func restoreTheme() {
        theme = theme.restored()
        values = theme.preset.values
        applyTheme()
    }

    /// Puts the reader's own colours in force, or refuses and says why.
    ///
    /// `reading-themes`: a pairing below 4.5:1 "is refused with the measured ratio
    /// stated". The refusal is returned rather than thrown or swallowed, because the
    /// sheet has to show the number — a refusal without one is just an obstacle.
    @discardableResult
    public func adoptColours(_ palette: ReaderPalette) -> Bool {
        guard palette.isReadable else { return false }
        theme = theme.adopting(palette)
        applyTheme()
        return true
    }

    /// Goes back to the preset's own colours, keeping its typography.
    public func discardCustomColours() {
        theme = theme.discardingCustomColours()
        applyTheme()
    }

    /// Turns publisher styles off by adopting a preset that overrides them.
    ///
    /// `reading-themes` requires an unavailable axis to offer "a single action that
    /// turns publisher styles off", and to preserve the reading position when it
    /// does. Readium re-lays out in place, so the position is kept by the navigator
    /// rather than by anything here.
    public func leavePublisherStyles() {
        guard theme.preset.keepsPublisherStyles else { return }
        adopt(.paper)
    }

    /// Writes the theme back, so the next book on this shelf opens the way this one
    /// was left.
    ///
    /// ponytail: reads and rewrites the whole blob per change. A drag now emits ten
    /// steps rather than one per frame, and the blob is a handful of small records,
    /// so this is cheaper than a debounce would be to get right. Debounce it if a
    /// reader with a thousand shelves ever notices.
    private func remember() {
        guard let preferences else { return }
        let stored = StoredTheme(theme: theme, values: values)
        preferences.save(
            preferences.themes().remembering(stored, for: Self.scope, shelf: shelf)
        )
    }

    private func applyTheme() {
        remember()
        guard let navigator else { return }

        // Where the reader is, before the reflow moves it.
        //
        // `ebook-reader`: "the reading position is preserved to the paragraph, not
        // the page number". Submitting preferences re-paginates the resource, and
        // Readium lands on the *progression* rather than the paragraph — measured on
        // an emulator, a size change moved the reader fourteen paragraphs back
        // inside the same chapter. Going to the stored locator afterwards puts them
        // where the text was.
        let locator = navigator.currentLocation
        navigator.submitPreferences(theme.preferences(values: values))

        guard let locator else { return }
        // ponytail: after the reflow, not during it. `submitPreferences` has no
        // completion, so this waits a frame's worth rather than observing the
        // relayout. If Readium ever exposes a settled signal, wait on that instead.
        Task {
            try? await Task.sleep(for: .milliseconds(Self.reflowSettle))
            _ = await navigator.go(to: locator, options: NavigatorGoOptions(animated: false))
        }
    }

    /// Long enough for Readium to re-paginate, short enough not to be seen.
    nonisolated private static let reflowSettle = 120

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
                initialLocation: resumed,
                // Without these a preference naming a bundled family resolves to
                // nothing and the page falls back silently.
                config: .init(fontFamilyDeclarations: FontDeclarations.all)
            )
            let observer = NavigatorObserver(model: self)
            self.observer = observer
            navigator.delegate = observer
            self.navigator = navigator
            // Submitted rather than passed at construction: the same call applies a
            // later change, so there is one path into Readium instead of two.
            navigator.submitPreferences(theme.preferences(values: values))
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
