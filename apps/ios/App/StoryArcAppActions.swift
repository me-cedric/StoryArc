import Formats
import LibraryFeature
import Persistence
import ReaderFeature
import Smb
import StoryArcCore
import SwiftUI

/// What the app does when something outside it asks: a file handed over, a quick action,
/// a volume finished, a reader closed.
///
/// Split from `StoryArcApp.swift` when that file passed the length the linter allows.
/// The scene, its state and its wiring stayed there; these are the actions that wiring
/// calls, and they read better as a list than as a tail on the scene.
extension StoryArcApp {

    /// Opens a publication the system handed over, or says why it cannot.
    ///
    /// Straight into the reader, per `local-library`: "the publication opens directly in
    /// the reader". No intermediate screen, because the reader already chose this file in
    /// another app and asking again would be asking twice.
    ///
    /// Remembered at the same time. The spec asks for the offer to be "once and
    /// unobtrusively", and a bookmark to the file the reader just chose to open is the
    /// least obtrusive form of it: nothing to dismiss, and the file is where they left it.
    func openHandedOver(_ url: URL) async {
        switch await OpenedFile.index(url) {
        case let .opened(publication):
            let selection = ReadingSelection(publication: publication, url: url)
            reading = selection
            dismissed = selection
            _ = OpenedFile.remember(url, in: bookmarks)
        case let .unsupported(detected):
            refusedFile = RefusedFile(name: url.lastPathComponent, detected: detected)
        case .unreadable:
            refusedFile = RefusedFile(name: url.lastPathComponent, detected: nil)
        }
    }

    /// The one moment progress is known to have changed. Called when the reader
    /// closes rather than on a timer or on every appearance, because this is the
    /// event — polling for it would be guessing.
    ///
    /// The same moment `kavita-server` sends a position: the reader has stopped, and the
    /// page they stopped on is the answer.
    /// Named rather than inline, because `onDismiss` and the content closure together
    /// are two trailing closures, which SwiftLint rejects.
    func dismissedReader() {
        refreshProgress(dismissed)
    }

    func refreshProgress(_ closed: ReadingSelection?) {
        Task {
            await library.refreshProgress()
            await reportToKavita(closed?.publication)
        }
    }

    /// Tells the server where the reader got to, when the publication came from one.
    func reportToKavita(_ publication: Publication?) async {
        guard let publication,
              let origin = kavitaProgress.origin(of: publication.id),
              let recorded = try? await progress?.progress(for: publication.identity),
              case let .page(index, _) = recorded.position
        else { return }

        let address = library.registry.sources
            .first { $0.id.uuidString == origin.sourceId }
            .flatMap { KavitaPage(source: $0, credentials: credentials)?.address }
        await KavitaSync.report(index, for: origin, to: address, in: kavitaProgress)
    }

    /// Swaps the reader's contents for the next publication.
    ///
    /// The selection is replaced rather than a second cover presented: stacking
    /// readers would leave a pile of them behind a long series.
    func openNext(_ publication: Publication) {
        guard let url = library.location(of: publication) else { return }
        let selection = ReadingSelection(publication: publication, url: url)
        reading = selection
        dismissed = selection
    }

    /// Puts the reader where a quick action asked to be, from wherever it found them.
    ///
    /// The library entry promises the *shelf*, so it undoes everything covering it: the
    /// reader, Settings, and the library's own navigation into a catalogue. The last of
    /// those is `@State` inside `LibraryView`, which nothing out here can reach — hence
    /// the counter, which the view watches and answers by unwinding itself. Android's
    /// `MainActivity` holds that stack directly and clears it in place; same landing,
    /// each platform's own way of getting there.
    func show(_ place: QuickActionRequest) {
        reading = nil
        isShowingSettings = false
        switch place {
        // A named publication never arrives here — `ReadingContinuity` waits for the
        // library to place it rather than handing it back. The shelf is the honest
        // landing if that ever changes.
        case .library, .continueReading:
            libraryRequests += 1
        case .downloads:
            downloads = downloadStore.library()
            isShowingDownloads = true
            isShowingSettings = true
        }
    }

    /// Copies a publication off a share and onto the device.
    ///
    /// The copying lives in `KeepForOffline.swift`, beside Android's own file of that
    /// name; what belongs here is only which publication the reader is then looking at.
    func keepForOffline(_ selection: ReadingSelection) async {
        guard let file = await keptForOffline(selection.url, into: downloadStore.directory) else { return }
        SmbReachability.clear()
        reading = ReadingSelection(publication: selection.publication, url: file)
        dismissed = reading
    }

    /// Returns both stores to what a fresh install has, and nothing more.
    ///
    /// Two stores, and only what each one calls a setting. The reading *defaults* are
    /// settings; a theme chosen while reading is not, and neither is progress.
    func resetSettings() {
        settingsStore.reset()
        settings = settingsStore.settings()
        let reader = ReaderPreferences()
        reader.save(reader.themes().clearingDefaults())
    }

    /// Writes through on every change, so the theme above recomposes with it.
    var settingsBinding: Binding<AppSettings> {
        Binding(
            get: { settings },
            set: { new in
                settings = new
                settingsStore.save(new)
            }
        )
    }
}

/// The five things a source's detail screen offers, resolved against the app's own stores.
///
/// `sources` names them all: test the connection, refresh, clear the cache, remove
/// downloads, remove the source. The first three are the library's; the last two also touch
/// the download store, which the scene owns rather than the library — so this is where the
/// two halves meet. Android's `MainActivity` carries the same switch.
extension StoryArcApp {
    func perform(_ action: SourceAction, on source: Source) async {
        switch action {
        case .testConnection: await library.test(source)
        case .refresh: await library.refresh(source)
        case .clearCache: library.clearCache(of: source)
        case .removeDownloads: removeDownloads(of: source)
        case .remove: removeSource(source)
        }
    }

    /// Removes a source, and everything `sources` says goes with it.
    ///
    /// The downloads first. The registry entry is what attributes a download to a source, so
    /// deleting the source before its files leaves bytes on disk that nothing in the app can
    /// name, let alone offer to remove.
    func removeSource(_ source: Source) {
        removeDownloads(of: source)
        library.remove(source, credentials: credentials)
    }

    /// Deletes the files one source produced, and the records of them.
    ///
    /// The source itself stays. `sources` lists this as its own action beside removal, and a
    /// reader freeing space before a flight has not asked to disconnect their server.
    func removeDownloads(of source: Source) {
        let (kept, removed) = downloads.removingAll(from: source.id)
        guard !removed.isEmpty else { return }
        for download in removed { downloadStore.remove(download) }
        downloads = kept
        downloadStore.save(kept)
    }
}
