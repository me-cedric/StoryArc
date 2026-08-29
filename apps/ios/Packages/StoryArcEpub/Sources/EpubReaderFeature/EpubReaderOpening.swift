public import Foundation

internal import SwiftUI
internal import UIKit

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
            self.opened = opened
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
    func totalProgression(of locator: Locator) -> Double {
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

    /// Turns a page with a transition StoryArc draws rather than one Readium draws.
    ///
    /// The order is the whole trick. A still of the outgoing page is taken *before* the
    /// navigator moves, the navigator then moves with no animation of its own, and the
    /// still is faded out over the page that arrived. Readium never animates, so the two
    /// do not fight.
    ///
    /// `page-transitions` calls this Fast fade, and it is the half of task 4.3b that needs
    /// one raster. Curl needs the incoming page as a second texture before it is on
    /// screen, which is a different problem.
    func turnWithFade(forward: Bool) async {
        guard let navigator, let page = navigator.view else { return }

        // Added to the navigator's own view, synchronously, rather than published as state
        // for SwiftUI to draw. That was the first attempt: setting state marks the model
        // dirty and SwiftUI renders on a later pass, so the `await` below let the navigator
        // swap its content while the still was not on screen yet — the new page flashed,
        // then the old one appeared over it. A subview added here is on screen in this
        // frame.
        let still = page.snapshotView(afterScreenUpdates: false)
        // A dip through the page's own colour, not a cross-fade. Two pages of body text do
        // not share a baseline grid, so dissolving one into the other shows every line
        // twice, half-offset — which reads as doubled text rather than as a fade, and is
        // exactly what a reader reported as "a mix of the pages". Fading out to the page
        // colour and back in from it never shows both at once.
        let dip = UIView(frame: page.bounds)
        dip.backgroundColor = page.backgroundColor ?? .systemBackground
        dip.alpha = 0
        dip.isUserInteractionEnabled = false

        if let still {
            still.frame = page.bounds
            still.isUserInteractionEnabled = false
            // The still first, the dip over it. The other order occludes the whole first
            // half: a still is opaque, so a dip fading in *underneath* it is invisible,
            // and the turn reads as the old page held still and then cut to the page
            // colour. Fading out means fading the page colour in over the outgoing page,
            // which is what the comment above describes and what this order does.
            page.addSubview(still)
            page.addSubview(dip)
        }

        let options = NavigatorGoOptions(animated: false)
        let moved = forward
            ? await navigator.goForward(options: options)
            : await navigator.goBackward(options: options)

        guard moved else {
            // At the end of the book. Both go at once rather than fading, because fading
            // would look like a turn that did not happen.
            still?.removeFromSuperview()
            dip.removeFromSuperview()
            return
        }
        guard let still else {
            dip.removeFromSuperview()
            return
        }

        // Out to the page colour, then in from it. Half the duration each, so the whole
        // turn still takes what `fadeDuration` says.
        let half = Self.fadeDuration / 2
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            UIView.animate(withDuration: half, delay: 0, options: [.curveEaseIn]) {
                dip.alpha = 1
            } completion: { _ in
                still.removeFromSuperview()
                UIView.animate(withDuration: half, delay: 0, options: [.curveEaseOut]) {
                    dip.alpha = 0
                } completion: { _ in
                    dip.removeFromSuperview()
                    continuation.resume()
                }
            }
        }
    }

    /// Short enough not to read as an animation, which is the point of the name.
    ///
    /// Slightly longer than the 0.18 a single cross-fade used, because this is two phases
    /// rather than one: out to the page colour and back in from it. Split across them, 0.09
    /// each was too quick to read as anything but a flicker.
    static let fadeDuration = 0.24

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
