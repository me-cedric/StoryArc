public import Foundation

internal import ReadiumNavigator
internal import ReadiumShared
internal import ReadiumStreamer

internal import StoryArcCore

// Getting the book on screen, and keeping the reader's place in it.
//
// Split out of `EpubReaderModel` so that file stays the reader's *state* — which theme,
// which typography, which transition — and this one is the lifecycle: open, navigate,
// record. They change for different reasons, which is the only reason worth splitting on.
extension EpubReaderModel {

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
            navigator.submitPreferences(theme.preferences(values: values, transition: transition))
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
    /// The rule lives in `StoryArcCore` so both platforms answer it the same way, and
    /// because it is subtler than it looks: in scroll mode Readium reports `0.0` rather
    /// than nothing, so trusting the report blindly leaves the reader at "0% read" for
    /// a whole chapter. See ``TotalProgression``.
    ///
    /// `ebook-reader` allows an approximation: what it forbids is presenting a
    /// reflowable *page number* as a stable identity. A percentage is the unit it asks
    /// for.
    private func totalProgression(of locator: Locator) -> Double {
        TotalProgression.resolve(
            reported: locator.locations.totalProgression,
            within: locator.locations.progression ?? 0,
            resourceIndex: readingOrder.firstIndex(of: locator.href.string) ?? -1,
            resourceCount: readingOrder.count
        )
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
/// Readium's delegate, held by the model.
///
/// Internal rather than private because the model's stored property is in the other file,
/// and a `private` type cannot be named from it.
final class NavigatorObserver: EPUBNavigatorDelegate {
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
