import DesignSystem
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
        case .passwordProtected:
            refusedFile = RefusedFile(name: url.lastPathComponent, detected: nil, isPasswordProtected: true)
        case .damaged:
            refusedFile = RefusedFile(name: url.lastPathComponent, detected: nil, isDamaged: true)
        case .solidArchive:
            refusedFile = RefusedFile(name: url.lastPathComponent, detected: nil, isSolidArchive: true)
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
            if let closed { await syncAfterLeaving(closed.publication) }
        }
    }

    /// Tells the server where the reader got to, when the publication came from one.
    ///
    /// A reflowable position -- an EPUB's -- used to have no case here at all, only
    /// `.page`, so an EPUB read from Kavita never reported anywhere. `KavitaOrigin.pageToReport`
    /// is what turns either kind of position into the page number Kavita's `progress`
    /// route wants; nil there means nothing to send, the same as before this fix.
    func reportToKavita(_ publication: Publication?) async {
        guard let publication,
              let origin = kavitaProgress.origin(of: publication.id),
              let recorded = try? await progress?.progress(for: publication.identity),
              let pageNum = origin.pageToReport(recorded.position)
        else { return }

        let address = library.registry.sources
            .first { $0.id.uuidString == origin.sourceId }
            .flatMap { KavitaPage(source: $0, credentials: credentials)?.address }
        await KavitaSync.report(pageNum, for: origin, to: address, in: kavitaProgress, progress: progress)
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
    ///
    /// - Parameter part: the chapter a listener chose on the publication page, zero-based, or
    ///   `nil` to start where the book was left. `audio-playback` requires a chosen chapter to
    ///   start "at that chapter rather than where the book was left". A session that is
    ///   already playing this book moves to that part, rather than being adopted where it
    ///   stands: a control that does nothing is the control this requirement forbids.
    func listen(to publication: Publication, at url: URL, startingAt part: Int? = nil) {
        let centre = PlayerCentre.shared
        guard centre.handover(opening: publication.id) != .adopt else {
            if let part { centre.play(part: part) }
            return
        }

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

            // **The book opens where the listener left it.** `NarratedSource.place` starts at
            // `.start` and moves only from the periodic observer that follows the audio, so
            // without this an audiobook began at zero however far into it a listener was. The
            // position was written the whole time and nothing read it back.
            //
            // A chapter the listener chose wins, and this is the other branch: `audio-playback`
            // asks a chosen chapter to start "at that chapter rather than where the book was
            // left", so a resume only happens when nothing was chosen.
            if part == nil, let place = await resumePlace(of: publication) {
                centre.play(part: place.part, offset: place.offset)
            }
            // After the session exists: ``PlayerCentre/play(part:)`` refuses while there is
            // none, and it moves the running session to the start of that part.
            if let part { centre.play(part: part) }
        }
    }

    /// The audiobook a listener was most recently in the middle of, or `nil` for a library
    /// nobody has listened to yet. Task 16.4, for ``CarScene/lastListened``.
    ///
    /// `progress.recent` is already ordered newest first, so the first unfinished listening
    /// position whose publication a car can start (``CarShelf/playable(_:at:)``) is the
    /// answer. The most recent entry may be a download since removed, which has no file.
    static func lastListenedBook(progress: ProgressStore?, library: LibraryModel) async -> SpokenBook? {
        guard let progress, let recent = try? await progress.recent(limit: 50) else { return nil }
        for entry in recent {
            guard case .listening = entry.position, !entry.isFinished,
                  let publication = library.publications.first(where: { $0.id == entry.identity.stableID }),
                  let book = CarShelf.playable(publication, at: library.location(of: publication))
            else { continue }
            return book
        }
        return nil
    }

    /// Where a listener stopped, if this publication carries a listening position.
    ///
    /// `nil` for a book never listened to, and `nil` for a page or a reflowable position: a
    /// comic read to page nine says nothing about a part index, and seeking on that number
    /// would put the listener somewhere arbitrary.
    ///
    /// **`nil` for a finished book, and that is the requirement rather than a nicety.**
    /// `reading-progress`: "reopening a finished publication starts at the beginning while
    /// retaining the finished record". `ReaderModel` drops the same override twice, for an
    /// archive and for a PDF. The player had no such guard, so a finished audiobook was
    /// seeked to its last second: the source reported the end, ``PlayerCentre/end()`` tore
    /// the session down, and the compact bar was withdrawn before it could be drawn — the
    /// book appeared to refuse to play. The record is untouched; only the seek is dropped.
    private func resumePlace(of publication: Publication) async -> (part: Int, offset: TimeInterval)? {
        guard let progress else { return nil }
        let stored = try? await progress.progress(for: publication.identity)
        guard let stored, !stored.isFinished,
              case let .listening(part, _, offset, _) = stored.position
        else { return nil }
        return (part, offset)
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
    /// - Parameter library: where the lock screen's artwork asks for a cover already decoded.
    ///   Task 16.10. A parameter rather than `self.library`, because this is called before
    ///   `_library` exists — see the call site.
    static func wirePlayerSpeed(_ preferences: PlaybackPreferences = PlaybackPreferences(), library: LibraryModel) {
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
        //
        // The cached half of ``LibraryModel/cover(for:maxPixelSize:)``, not the fetching
        // half: ``PlayerCentre/onArtwork`` is asked synchronously, from inside a periodic
        // publish this cannot suspend. The common case is already covered — a reader who
        // opened the book from a shelf, where the cover was already decoded.
        centre.onArtwork = { book in
            PlayerArtworkImage.png(
                format: book.publication.format,
                cover: library.cachedCover(for: book.publication)
            )
        }
    }

    /// Swaps the reader's contents for the next publication. The selection is replaced rather
    /// than a second cover presented: stacking readers would leave a pile of them behind.
    func openNext(_ publication: Publication) {
        guard let url = library.location(of: publication) else {
            Task { await openFetched(publication) } // Tasks 7.3 and 7.14: see `NextEntryOpening.swift`.
            return
        }
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
    ///
    /// Returns whether the copy landed. On `false` the share is still unreachable, which is
    /// why this was offered at all, and `NetworkNotice` tells the reader the attempt did not
    /// land.
    @discardableResult
    func keepForOffline(_ selection: ReadingSelection) async -> Bool {
        guard let copy = await keptForOffline(selection, into: downloadStore.directory) else { return false }
        downloadStore.save(
            downloadStore.library().queueing(
                Download.finishedCopy(
                    of: selection.publication,
                    remote: selection.url,
                    mediaType: copy.mediaType,
                    bytes: copy.bytes
                )
            )
        )
        reading = ReadingSelection(publication: selection.publication, url: copy.file)
        dismissed = reading
        return true
    }

    /// Returns both stores to what a fresh install has, and nothing more.
    ///
    /// Two stores, and only what each one calls a setting. The reading *defaults* are
    /// settings; a theme chosen while reading is not, and neither is progress. Natural
    /// lives under its own key (`NaturalTheme.storageKey`), outside both stores, so a
    /// reset has to remove it explicitly or Appearance does not "go back to how it
    /// started".
    func resetSettings() {
        settingsStore.reset()
        settings = settingsStore.settings()
        UserDefaults.standard.removeObject(forKey: NaturalTheme.storageKey)
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
