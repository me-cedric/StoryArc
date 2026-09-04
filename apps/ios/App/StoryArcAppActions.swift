import Formats
import LibraryFeature
import Persistence
import Playback
import PlayerFeature
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
            open(publication, at: url)
            _ = OpenedFile.remember(url, in: bookmarks)
        case let .unsupported(detected):
            refusedFile = RefusedFile(name: url.lastPathComponent, detected: detected)
        case .contentProtected:
            refusedFile = RefusedFile(name: url.lastPathComponent, detected: nil, isProtected: true)
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

    /// Opens a publication: a reader for a comic or a book, the player for an audiobook.
    ///
    /// **One seam, so every way in agrees.** A publication reaches the app from the shelf,
    /// from a quick action, from a file another app handed over and from the end of the
    /// previous issue, and each of those used to build a `ReadingSelection` itself. An
    /// audiobook opened that way would have been handed to a comic reader, which is the
    /// defect `publication-formats` describes as opening "in the player rather than in a
    /// reader".
    ///
    /// It asks `format.isAudio` rather than listing the audio formats, so a format added
    /// later cannot miss this branch.
    func open(_ publication: Publication, at url: URL) {
        guard !publication.format.isAudio else {
            listen(to: publication, at: url)
            return
        }
        let selection = ReadingSelection(publication: publication, url: url)
        reading = selection
        dismissed = selection
    }

    /// Starts, or returns to, an audiobook.
    ///
    /// `audio-playback`: opening the book that is already playing must not restart it, which
    /// is what `SessionHandover` answers with `adopt` — so a listener who taps the same cover
    /// again keeps their place instead of losing it.
    ///
    /// No screen is presented. The compact bar is the surface a listener gets, and it is
    /// already above the navigation control; presenting the full player over the shelf would
    /// take them away from what they were doing, which is the opposite of what playback
    /// outliving the publication is for.
    func listen(to publication: Publication, at url: URL) {
        let centre = PlayerCentre.shared
        guard centre.handover(opening: publication.id) != .adopt else { return }

        Task {
            // The scope has to be open for the whole session, not just the read: an
            // `AVPlayer` keeps reading the file for as long as it plays, and a library
            // folder the reader picked in a document picker is reachable only inside one.
            // `OpenedFile.index` opens and closes a scope around its read for the same
            // reason; the difference here is that the read is not the end of the story.
            let scoped = url.startAccessingSecurityScopedResource()

            let book = publication.format == .audioFolder
                ? await AudiobookReader.read(folderAt: url)
                : await AudiobookReader.read(fileAt: url)
            // A book with no parts is a file nothing can play. Better to leave the shelf as
            // it was than to open a player with nothing in it.
            guard !book.parts.isEmpty else {
                if scoped { url.stopAccessingSecurityScopedResource() }
                return
            }

            // The audio session and the lock screen, made once and kept: wiring them per
            // session is how a listener who started five books ends up with five handlers
            // on every lock-screen button. Read-aloud asks for the same thing at the same
            // seam — `ReadAloudCentre.begin` — because one player owes one platform half.
            centre.adoptSystemPlatform()
            wirePlayerRecording()
            centre.begin(
                SpokenBook(publication: publication, url: url),
                source: NarratedSource(book)
            )
        }
    }

    /// Sends the player's positions to the store, once.
    ///
    /// `reading-progress`: an audiobook's position "survives the app being closed, the device
    /// restarting, and the file being re-downloaded, exactly as a page index does" — and it is
    /// `PlayerCentre` that knows where the audio is, on every part change and before every
    /// ending, so this is only the wire between the two.
    ///
    /// **Only an audiobook writes a listening position, and that is `reading-progress` by
    /// name**: "a publication that has been read aloud and then read silently … has one
    /// position … the app does not keep a separate listening position, so returning never
    /// offers a choice of two places". A publication read aloud is still a reflowable
    /// publication, and what the voice writes for it is the reflowable position the eye would
    /// have written — `SpokenPosition` in `StoryArcEpub`, unchanged. Writing a second,
    /// time-shaped position for the same book here is exactly the choice of two places the
    /// spec forbids. `publication.format.isAudio` is the honest way to ask, because
    /// `audio-playback` calls the source "a fact about the file".
    ///
    /// Wired once. `onRecord` is a single closure, and re-assigning it per session would be
    /// harmless but pointless; the guard says which it is.
    func wirePlayerRecording() {
        let centre = PlayerCentre.shared
        guard centre.onRecord == nil else { return }
        let store = progress
        centre.onRecord = { reached in
            guard reached.book.publication.format.isAudio, let store else { return }
            let record = ReadingProgress(
                identity: reached.book.publication.identity,
                position: reached.position,
                isFinished: reached.isFinished,
                updatedAt: Date()
            )
            Task { try? await store.save(record) }
        }
    }

    /// Remembers how fast a listener wants a book read, and asks before the first sound.
    ///
    /// `audio-playback`: the speed "is remembered for that publication and offered as the
    /// default for others in the same series". ``PlaybackPreferences`` is the whole of that
    /// rule — two scopes resolved publication-then-series, and a choice writing both — and this
    /// is only the wire between it and the player. Android's half is
    /// `PlaybackHost.start(speed:)` reading the same store.
    ///
    /// **Static, and called from `StoryArcApp.init`**, which is what makes it reach *both*
    /// sources. `wirePlayerRecording()` is called from `listen(to:at:)`, so a listener who only
    /// ever read a book aloud would never have run it — and read-aloud starts its session from
    /// `ReadAloudCentre.begin`, deep inside `StoryArcEpub`, which cannot see this target. One
    /// call at start-up is the only place that covers a session begun from either.
    ///
    /// **Before the first sound rather than after it**: ``PlayerCentre/begin(_:source:)`` asks
    /// `onRecallSpeed` and calls `setSpeed` before `play`, so a listener never hears the
    /// sentence that is about to be announced as the start of a chapter at the wrong pace.
    /// How far a skip moves, restored before the first sound and kept when it changes.
    ///
    /// **`skipIntervals` had no setter anywhere in the app until 2026-09-03**, so every listener
    /// got the product defaults for ever and `audio-playback`'s "an interval the listener can
    /// configure" was unmet with nothing failing. Applied here rather than on the first play,
    /// for the reason the speed's own wiring gives: a value restored *after* a session starts is
    /// a control that changes under a listener who has already pressed something.
    ///
    /// Global rather than per publication — see ``PlayerCentre/setSkipIntervals(_:)``.
    static func wirePlayerSkip(_ preferences: SkipPreferences = SkipPreferences()) {
        let centre = PlayerCentre.shared
        guard centre.onRememberSkip == nil else { return }

        centre.skipIntervals = preferences.intervals()
        centre.onRememberSkip = { intervals in preferences.remember(intervals) }
    }

    static func wirePlayerSpeed(_ preferences: PlaybackPreferences = PlaybackPreferences()) {
        let centre = PlayerCentre.shared
        guard centre.onRecallSpeed == nil else { return }

        centre.onRecallSpeed = { publication in
            PlaybackSpeed(preferences.speed(of: publication.id, series: publication.series))
        }
        centre.onRememberSpeed = { publication, speed in
            preferences.remember(speed.rate, of: publication.id, series: publication.series)
        }
        // The picture the lock screen shows, drawn by the same view the full player draws.
        // `audio-playback`: the system's own media controls get "that same artwork, because a
        // lock screen showing a headphones symbol is the one place a listener looks for an
        // hour". Wired here rather than in `Playback`, which has no SwiftUI and must not.
        centre.onArtwork = { book in
            PlayerArtworkImage.png(format: book.publication.format)
        }
    }

    /// Swaps the reader's contents for the next publication.
    ///
    /// The selection is replaced rather than a second cover presented: stacking
    /// readers would leave a pile of them behind a long series.
    func openNext(_ publication: Publication) {
        guard let url = library.location(of: publication) else { return }
        open(publication, at: url)
    }

    /// Puts the reader where a quick action asked to be, from wherever it found them.
    ///
    /// Both entries now name a destination the shell already has, which is what
    /// `navigation-shell` means by opening "there instead". Downloads in particular used
    /// to open *Settings*, scrolled to a section inside it — the only place the app kept
    /// what a reader needs before a flight.
    ///
    /// The library entry promises the *shelf*, so it also undoes everything covering it:
    /// the reader, Settings, and the library's own navigation into a source. The last of
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
            tab = .destination(.library)
            libraryRequests += 1
        case .downloads:
            downloads = downloadStore.library()
            tab = .destination(.onDevice)
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
        // The sheet the source was added through, re-opened with everything but the secret.
        // Presented from here rather than run here, because the answer arrives when the
        // reader has finished typing.
        case .reconnect: reconnecting = source
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
        // What a Kavita server said about those downloads goes with them. A card left behind
        // describes bytes nobody has: it corrupts nothing, and it would put a row in an
        // offline search that opens nothing.
        KavitaCardStore().removeAll(from: source.id.uuidString)
    }
}
