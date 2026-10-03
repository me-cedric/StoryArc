import Catalogue
import DesignSystem
import EpubReaderFeature
import LibraryFeature
import Persistence
import Playback
import ReaderFeature
import SettingsFeature
import Formats
import Smb
import StoryArcCore
import SwiftUI

@main
struct StoryArcApp: App {
    // The state below is internal rather than private because the actions that read it
    // live in `StoryArcAppActions.swift`, and `private` does not reach across a file.
    // Internal, not public: this is the app target, so nothing outside it can see them.
    @Environment(\.scenePhase) private var scenePhase

    /// `comic-reader` locks the reader's orientation, and an application delegate is the
    /// only place UIKit will take that answer from. See `OrientationDelegate`.
    @UIApplicationDelegateAdaptor(OrientationDelegate.self) private var orientation

    /// `settings-and-about`: System by default, applied without a restart.
    /// Stored here rather than in a store so the shell has no dependency on a
    /// persistence layer that does not exist yet.
    /// Everything Settings holds, and the store behind it.
    ///
    /// Held here rather than inside the settings screen: `settings-and-about` requires an
    /// appearance to apply "immediately across the whole app without a restart", and
    /// *immediately* means while the reader is still looking at the picker. A screen that
    /// owned its own copy and handed it back on the way out would change the theme one
    /// screen too late.
    ///
    /// It replaces an `@AppStorage("appearanceMode")` that predated the settings store —
    /// two homes for one value, and only one of them was ever written.
    @State var settings = SettingsStore().settings()
    let settingsStore = SettingsStore()

    @State var isShowingSettings = false

    /// Which of the shell's tabs the reader is on.
    ///
    /// `navigation-shell`: the app opens on the home surface, and opens somewhere else
    /// only when the launch named somewhere else — a quick action, a handover, a shortcut.
    /// Held here rather than inside ``AppShell`` because those three arrive at the app,
    /// not at the tab bar.
    @State var tab: AppShell.Selection = .destination(.home)

    /// Whether Settings should open straight at Downloads, because a quick action asked
    /// for it rather than the reader tapping their way in.
    @State var isShowingDownloads = false

    /// How many times the reader has asked to be taken back to the shelf. See
    /// ``show(_:)``.
    @State var libraryRequests = 0

    /// What the reader is currently showing, if anything.
    ///
    /// The app layer owns this because a feature module never depends on another
    /// feature module (docs/architecture) — the library reports a choice and the
    /// reader accepts one, and neither knows the other exists.
    @State var reading: ReadingSelection?

    /// What was open a moment ago. `onDismiss` runs after the item is cleared, and the
    /// position has to be sent for the publication that was being read, not for nothing.
    @State var dismissed: ReadingSelection?

    /// One store for the whole app. ADR-0006 makes the local record authoritative,
    /// so the reader writing and the library reading have to be the same store —
    /// two would disagree about where the user is.
    ///
    /// Not `private`: the sweep in `FinishedDownloadSweep.swift` is the other half of
    /// this type, and Swift's `private` is file-scoped.
    let progress: ProgressStore?

    /// Held here so the app can refresh it when the reader closes.
    @State var library: LibraryModel

    /// A file the system handed over that StoryArc cannot read, if any.
    ///
    /// Held rather than discarded: `local-library` requires the app to name the format it
    /// detected instead of failing silently, and a reader who picked the wrong file needs
    /// to know it was the file rather than the app.
    @State var refusedFile: RefusedFile?
    /// Why a taken next-entry offer did not open, if it did not. See `NextEntryOpening.swift`.
    @State var nextEntryFailure: String?

    let bookmarks = FolderBookmarks()

    /// The link between a publication the reader just closed and the Kavita chapter it came
    /// from. Held here because this is where the reader closes.
    let kavitaProgress = KavitaProgressStore()
    let credentials = CredentialStore()

    /// What is on the device. Held here because Settings can be reached without ever
    /// opening a catalogue, and re-read on each appearance so a download made while
    /// browsing shows up.
    let downloadStore = DownloadStore()
    @State var downloads = DownloadStore().library()

    /// A download removed because the reader finished it, and the bytes waiting in case
    /// they change their mind. `offline-downloads` gives them ten seconds.
    @State var removedDownload: RemovedDownload?

    /// The source whose credential is being re-entered, when one is.
    ///
    /// `sources` asks for "a single action to re-enter credentials" on a refused source, and
    /// the action is pressed on a screen inside Settings — which is a sheet, so the answer
    /// has to be presented from the layer that owns it.
    @State var reconnecting: Source?

    init() {
        // `offline-downloads`' *Reading while downloading*. Without this line the ranged
        // reader is built, tested and unreachable: nothing else registers `http`, so an
        // acquisition URL handed to `ComicArchiveOpener` would be opened as a local file.
        //
        // `SourceRangeTransport` rather than the default: a streamed read has to carry the
        // same credential and trust the same certificates the download queue does, or a
        // catalogue behind Basic, Bearer or a pinned self-signed certificate answers 401 or
        // fails TLS the moment a reader opens a book while it is still arriving — dl-core 1.6.
        HttpSource.register(
            transport: SourceRangeTransport(
                pins: .app,
                credentials: CredentialStore(),
                sources: { SourceStore().registry().sources }
            )
        )

        // dl-core 1.3: the queue used to come to life only when a reader opened a catalogue
        // page, so a background completion arriving before that had no queue to adopt it —
        // `BackgroundTransfers` deleted an orphaned file with no handler registered for it —
        // and a download the reader left held for Wi-Fi never resumed until some page was
        // opened. Built here, before any screen, it is also the first caller of
        // `BackgroundTransfers.shared(pins:)` on every launch, background relaunches
        // included, so the background session's trust and its orphan and resumable handlers
        // are set from this app-wide pin set rather than from whichever page happened to be
        // the first one opened.
        _ = DownloadQueue.shared()

        // How the reader reaches a share. Registered here because this is where the source
        // registry and the credential store both are; `Formats` stays unaware that SMB
        // exists, which is the only way that dependency can point.
        ComicArchiveOpener.register(scheme: "smb") { url in
            let credentials = CredentialStore()
            let sources = SourceStore().registry().sources
            guard let (page, inside) = sources.lazy
                .compactMap({ SmbPage(source: $0, credentials: credentials) })
                .compactMap({ page in SmbLocator.inside(url, of: page.address).map { (page, $0) } })
                .first
            else { throw SmbError.shareNotFound }
            return try await SmbClient(address: page.address).open(inside)
        }

        let store = try? ProgressStore()
        self.progress = store
        let library = LibraryModel(
            progress: store,
            bookmarks: FolderBookmarks(),
            preferences: LibraryPreferences(),
            sourceStore: SourceStore(),
            // Without this the model keeps its shelves in memory only: every
            // collection and reading list a reader made was gone on the next launch,
            // and `ShelvesStore` — which exists, is tested, and is written to on every
            // edit — was never read by the app that ships.
            shelvesStore: ShelvesStore(),
            // One store, two readers of it: what was downloaded joins the one
            // library rather than being reachable only by browsing back to the server
            // it came from, and imported copies live in it too — see `ImportedCopies`.
            downloadStore: DownloadStore(),
            journal: ScanJournal()
        )
        _library = State(initialValue: library)

        // The speed a listener chose, remembered per publication and offered to the rest of the
        // series. Here rather than beside the session's other wiring because a session can
        // begin from either source and only one of the two paths runs through this target —
        // see `wirePlayerSpeed`. After `library` exists: its lock-screen artwork reads the
        // library's own cover cache.
        Self.wirePlayerSpeed(library: library)
    }

    var body: some Scene {
        WindowGroup {
            AppShell(
                tab: $tab,
                model: library,
                progress: progress,
                // One seam for every way in — see `open(_:at:)`. An audiobook goes to the
                // player and everything else to a reader.
                onOpen: { publication, url in open(publication, at: url) },
                // The other request the page makes: `audio-playback` requires a chapter
                // chosen there to start at that chapter rather than where the book was left.
                onListen: { publication, url, part in
                    listen(to: publication, at: url, startingAt: part)
                },
                onOpenSettings: {
                    // Re-read on the way in, so a download made while browsing a catalogue
                    // is on this screen rather than one launch behind it.
                    downloads = downloadStore.library()
                    isShowingDownloads = false
                    isShowingSettings = true
                },
                showLibrary: libraryRequests,
                // The one place that knows. A reader is presented *over* the shelf, so the
                // shelf cannot see it — and `sources` forbids automatic recovery from
                // interrupting reading, which is checked each time the backoff comes round
                // rather than once, because a reader opens a publication while it waits.
                isReading: { reading != nil }
            )
            .storyArcTheme(appearance: settings.appearance)
            .speaking(settings.language)
            // The shelf is drawn from a stored, already-collated list, so it does not follow
            // the language the way a `Text` does — see `LibraryModel.languageChanged()`.
            // `speaking` above has already applied the new choice by the time this runs: it
            // takes effect while the body is built, and an `onChange` action runs after that.
            .onChange(of: settings.language) { library.languageChanged() }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView(
                    settings: settingsBinding,
                    readerStore: ReaderPreferences(),
                    onReset: resetSettings,
                    opensAtDownloads: isShowingDownloads,
                    sources: library.registry.sources,
                    itemCount: { library.itemCount(of: $0) },
                    isPartial: { library.isPartial($0) },
                    readCount: { library.readProgress(of: $0)?.read },
                    readTotal: { library.readProgress(of: $0)?.total },
                    onRemoveSource: removeSource,
                    onRenameSource: { library.rename($0, to: $1) },
                    onReorderSource: { library.move($0, to: $1) },
                    onSourceAction: { await perform($1, on: $0) },
                    // Read from the store rather than from a browser's acquisition: the
                    // store is the record, and Settings can be reached without ever having
                    // opened a catalogue.
                    downloads: downloads,
                    bytesOnDisk: downloadStore.bytesOnDisk(),
                    // The imported share of that total. `local-library` asks the app to
                    // report the space an import used, and this is the only screen that
                    // states a storage figure at all. Android's `SettingsHost` reads the
                    // same value from the same accessor.
                    importedBytes: library.importedBytes,
                    // Removing one download and reordering the queue left with the files:
                    // both are the Downloads destination's now, which is where a reader
                    // looks for them and where they are one tap away rather than four.
                    onClearDownloads: {
                        // The bytes behind the undo are staged *inside* the downloads
                        // directory, so clearing already takes them with it. Dropping the
                        // pending removal is what stops a later undo putting a record back
                        // for bytes nobody has. Android has the same two lines.
                        removedDownload = nil
                        DownloadQueue.shared().clearing()
                        downloads = DownloadQueue.shared().library
                    },
                    onRemoveFinished: removeFinished,
                    onRestoreFinished: restoreFinished
                )
                    .storyArcTheme(appearance: settings.appearance)
                    .speaking(settings.language)
                    // Over Settings, because that is where the action was pressed and the
                    // reader has not asked to leave the screen they were diagnosing.
                    .sheet(item: $reconnecting) { source in
                        SourceReconnectSheet(source: source) { reconnected in
                            library.reconnect(reconnected)
                            reconnecting = nil
                        }
                        .storyArcTheme(appearance: settings.appearance)
                        .speaking(settings.language)
                    }
            }
            // The system hands a file over here, and until this existed it was dropped.
            // `Info.plist` declares StoryArc as a handler for six formats, so the app was
            // offered, chosen, and then showed its library as if nothing had happened.
            // `offline-downloads`: a finished publication's download goes, and the reader
            // has ten seconds to say otherwise. Swept when the library appears rather than
            // in a reader's close path, because there are two readers and this is the one
            // moment both of them pass through.
            .task(id: reading?.id) {
                // Not gated on the sweep setting: a removal asked for on the end screen
                // (D7) goes here too. `sweepFinishedDownload` checks the setting itself.
                guard reading == nil else { return }
                await sweepFinishedDownload()
            }
            .onOpenURL { url in Task { await openHandedOver(url) } }
            // Task 16.4: what a CarPlay scene asks the app for, installed once `library`
            // and `progress` both exist. `CarSceneDelegate` reaches none of these directly
            // — a car scene is not SwiftUI's scene, so it has no environment to read.
            .task {
                CarScene.onDevice = {
                    library.publications.compactMap { CarShelf.playable($0, at: library.location(of: $0)) }
                }
                CarScene.onListen = { book in listen(to: book.publication, at: book.url) }
                CarScene.lastListened = { await lastListenedBook() }
            }
            // Closing the reader is not the only way a reader leaves it. A phone is
            // usually closed by going home, and a position that only travelled on a
            // clean exit would be the evening's reading lost.
            .onChange(of: scenePhase) { _, phase in
                // `.background` alone, not "anything but active". `.inactive` arrives for a
                // notification banner, a control-centre pull and the app switcher, none of
                // which is the reader leaving, and each of which would write again.
                guard phase == .background else { return }
                // And a listener is closed the same way. `audio-playback` asks a listening
                // position to be written when the app leaves the foreground, because this is
                // the last moment before the system may reclaim the process. The audio itself
                // carries on, so this writes and stops nothing.
                PlayerCentre.shared.recordReached()
                Task { await reportToKavita(reading?.publication ?? dismissed?.publication) }
            }
            .refusing($refusedFile)
            // `native-experience`: the home-screen menu, Handoff and Spotlight. All three
            // name a publication and none of them can open one, so the waiting lives in
            // `ReadingContinuity` and this hands it the three ways back in.
            .continuing(
                reading: reading,
                library: library,
                hasDownloads: !downloads.downloads.isEmpty,
                onOpen: openNext,
                onShow: show
            )
            .fullScreenCover(item: $reading, onDismiss: dismissedReader) { selection in
                // Full screen, not a sheet: `comic-reader` wants nothing on screen
                // while reading, and a sheet keeps a card edge and the view behind
                // it in view.
                // Two readers, chosen by what the publication *is* rather than by
                // a mode the user picks. A reflowable book is laid out by a
                // rendering engine (ADR-0005); a comic is a list of images and
                // needs none. A fixed-layout EPUB is the third case and belongs
                // with the comic reader — it has pages, at a fixed aspect ratio —
                // which is what `ebook-reader` asks for.
                if selection.publication.isReflowable {
                    EpubReaderView(
                        publication: selection.publication,
                        url: selection.url,
                        progress: progress,
                        preferences: ReaderPreferences(),
                        bookmarks: BookmarkStore(),
                        annotations: AnnotationStore(),
                        // The settings rather than the preset they resolve to: "System"
                        // is a question about the device, and an `App` sits outside every
                        // view hierarchy, so a colour scheme read here never moves. The
                        // reader resolves it from its own environment.
                        settings: settings,
                        // `collections-and-reading-lists` tasks 7.2, 7.3 and 7.14: the
                        // reflowable reader offers what comes next at the end, the way
                        // the paged reader's own end screen does.
                        next: library.offeredNext(after: selection.publication),
                        onOpenNext: openNext
                    )
                    .nextEntryFailure($nextEntryFailure)
                    // Identity, so opening the next issue from the end screen
                    // builds a fresh reader rather than reusing the previous one's
                    // `@State`.
                    .id(selection.publication.id)
                    .storyArcTheme(appearance: settings.appearance)
                    .speaking(settings.language)
                } else {
                    ReaderView(
                        publication: selection.publication,
                        url: selection.url,
                        progress: progress,
                        preferences: ReaderPreferences(),
                        // The same store the reflowable reader writes to. A PDF that carries
                        // text is marked the same way a novel is, and `ebook-reader` lists
                        // both in one place.
                        annotations: AnnotationStore(),
                        // `comic-reader`'s chapter actions and its end screen both ask what
                        // surrounds this issue, and only the app layer sees both the reader
                        // and the library — including a list, whose order beats the series.
                        // Tasks 7.3 and 7.14: a server list the reader is inside beats both,
                        // and nothing is offered that choosing it could not open.
                        previousInSeries: library.offeredPrevious(before: selection.publication),
                        nextInSeries: library.offeredNext(after: selection.publication),
                        onOpen: openNext,
                        downloadCleanup: downloadCleanupOffer(for: selection.publication),
                        // Only for a publication that lives on a share. Everything else is
                        // already on the device, and offering to download it would be
                        // offering nothing.
                        onDownloadForOffline: selection.url.scheme == "smb"
                            ? { await keepForOffline(selection) }
                            : nil
                    )
                    .nextEntryFailure($nextEntryFailure)
                    // `page-transitions` makes the turn zones a setting, and the reader is a
                    // module that does not read the settings store.
                    .environment(\.turnPagesByTappingTheEdges, settings.turnPagesByTappingTheEdges)
                    .storyArcTheme(appearance: settings.appearance)
                    .speaking(settings.language)
                }
            }
        }
        .continuingDownloadsInBackground()
    }
}
