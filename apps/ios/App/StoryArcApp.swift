import DesignSystem
import EpubReaderFeature
import LibraryFeature
import Persistence
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
    @Environment(\.colorScheme) private var colorScheme
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
        // How the reader reaches a share. Registered here because this is where the source
        // registry and the credential store both are; `Formats` stays unaware that SMB
        // exists, which is the only way that dependency can point.
        ComicArchiveOpener.register(scheme: "smb") { url in
            let credentials = CredentialStore()
            let sources = SourceStore().registry().sources
            guard let page = sources.lazy
                .compactMap({ SmbPage(source: $0, credentials: credentials) })
                .first(where: { url.absoluteString.hasPrefix(SmbLocator.write($0.address)) })
            else { throw SmbError.shareNotFound }

            // Decoded, not as it appears in the URL: a filename with a space arrives as
            // `%20`, and the server has no such file.
            let encoded = url.absoluteString
                .replacingOccurrences(of: SmbLocator.write(page.address), with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let inside = encoded.removingPercentEncoding ?? encoded
            return try await SmbClient(address: page.address).open(inside)
        }

        let store = try? ProgressStore()
        self.progress = store
        _library = State(
            initialValue: LibraryModel(
                progress: store,
                bookmarks: FolderBookmarks(),
                preferences: LibraryPreferences(),
                sourceStore: SourceStore(),
                // One store, two readers of it: what was downloaded joins the one
                // library rather than being reachable only by browsing back to the server
                // it came from, and imported copies live in it too — see `ImportedCopies`.
                downloadStore: DownloadStore(),
                journal: ScanJournal()
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            AppShell(
                tab: $tab,
                model: library,
                progress: progress,
                onOpen: { publication, url in
                    let selection = ReadingSelection(publication: publication, url: url)
                    reading = selection
                    dismissed = selection
                },
                onOpenSettings: {
                    // Re-read on the way in, so a download made while browsing a catalogue
                    // is on this screen rather than one launch behind it.
                    downloads = downloadStore.library()
                    isShowingDownloads = false
                    isShowingSettings = true
                },
                showLibrary: libraryRequests
            )
            .storyArcTheme(appearance: settings.appearance)
            .speaking(settings.language)
            .sheet(isPresented: $isShowingSettings) {
                SettingsView(
                    settings: settingsBinding,
                    readerStore: ReaderPreferences(),
                    onReset: resetSettings,
                    opensAtDownloads: isShowingDownloads,
                    sources: library.registry.sources,
                    itemCount: { library.itemCount(of: $0) },
                    onRemoveSource: removeSource,
                    onRenameSource: { library.rename($0, to: $1) },
                    onReorderSource: { library.move($0, to: $1) },
                    onSourceAction: { await perform($1, on: $0) },
                    // Read from the store rather than from a browser's acquisition: the
                    // store is the record, and Settings can be reached without ever having
                    // opened a catalogue.
                    downloads: downloads,
                    bytesOnDisk: downloadStore.bytesOnDisk(),
                    onRemoveDownload: { download in
                        downloads = downloadStore.removing(download.id, from: downloads)
                        // The library holds a row for every imported copy, and a row whose
                        // file has just been deleted is a book that opens onto nothing.
                        Task { await library.refreshImports() }
                    },
                    onReorderDownload: { download, later in
                        downloads = downloads.moving(download.id, later: later)
                        downloadStore.save(downloads)
                    },
                    onClearDownloads: {
                        // The bytes behind the undo are staged *inside* the downloads
                        // directory, so clearing already takes them with it. Dropping the
                        // pending removal is what stops a later undo putting a record back
                        // for bytes nobody has. Android has the same two lines.
                        removedDownload = nil
                        downloads = downloadStore.clearing()
                    }
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
                guard reading == nil, settings.removeDownloadsAfterFinishing else { return }
                await sweepFinishedDownload()
            }
            .onOpenURL { url in Task { await openHandedOver(url) } }
            // Closing the reader is not the only way a reader leaves it. A phone is
            // usually closed by going home, and a position that only travelled on a
            // clean exit would be the evening's reading lost.
            .onChange(of: scenePhase) { _, phase in
                guard phase != .active else { return }
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
                if selection.publication.format == .epub, !selection.publication.isFixedLayout {
                    EpubReaderView(
                        publication: selection.publication,
                        url: selection.url,
                        progress: progress,
                        preferences: ReaderPreferences(),
                        bookmarks: BookmarkStore(),
                        annotations: AnnotationStore(),
                        linkedPreset: linkedPreset(for: settings, in: colorScheme)
                    )
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
                        previousInSeries: library.previous(before: selection.publication),
                        nextInSeries: library.next(after: selection.publication),
                        onOpen: openNext,
                        blockedSince: { SmbReachability.blockedSince },
                        onDismissTrouble: { SmbReachability.clear() },
                        // Only for a publication that lives on a share. Everything else is
                        // already on the device, and offering to download it would be
                        // offering nothing.
                        onDownloadForOffline: selection.url.scheme == "smb"
                            ? { Task { await keepForOffline(selection) } }
                            : nil
                    )
                    .storyArcTheme(appearance: settings.appearance)
                    .speaking(settings.language)
                }
            }
        }
        .continuingDownloadsInBackground()
    }
}
