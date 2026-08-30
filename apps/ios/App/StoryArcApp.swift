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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    /// `comic-reader` locks the reader's orientation, and an application delegate is the
    /// only place UIKit will take that answer from. See `OrientationDelegate`.
    @UIApplicationDelegateAdaptor(OrientationDelegate.self) private var orientation

    @State private var settings = SettingsStore().settings()
    private let settingsStore = SettingsStore()

    @State private var isShowingSettings = false

    /// Whether Settings should open straight at Downloads, because a quick action asked
    /// for it rather than the reader tapping their way in.
    @State private var isShowingDownloads = false

    /// How many times the reader has asked to be taken back to the shelf. See
    /// ``show(_:)``.
    @State private var libraryRequests = 0

    /// What the reader is currently showing, if anything.
    ///
    /// The app layer owns this because a feature module never depends on another
    /// feature module (docs/architecture) — the library reports a choice and the
    /// reader accepts one, and neither knows the other exists.
    @State private var reading: ReadingSelection?

    /// What was open a moment ago. `onDismiss` runs after the item is cleared, and the
    /// position has to be sent for the publication that was being read, not for nothing.
    @State private var dismissed: ReadingSelection?

    /// One store for the whole app. ADR-0006 makes the local record authoritative,
    /// so the reader writing and the library reading have to be the same store —
    /// two would disagree about where the user is.
    ///
    /// Not `private`: the sweep in `FinishedDownloadSweep.swift` is the other half of
    /// this type, and Swift's `private` is file-scoped.
    let progress: ProgressStore?

    /// Held here so the app can refresh it when the reader closes.
    @State private var library: LibraryModel

    /// A file the system handed over that StoryArc cannot read, if any.
    ///
    /// Held rather than discarded: `local-library` requires the app to name the format it
    /// detected instead of failing silently, and a reader who picked the wrong file needs
    /// to know it was the file rather than the app.
    @State private var refusedFile: RefusedFile?

    private let bookmarks = FolderBookmarks()

    /// The link between a publication the reader just closed and the Kavita chapter it came
    /// from. Held here because this is where the reader closes.
    private let kavitaProgress = KavitaProgressStore()
    private let credentials = CredentialStore()

    /// What is on the device. Held here because Settings can be reached without ever
    /// opening a catalogue, and re-read on each appearance so a download made while
    /// browsing shows up.
    let downloadStore = DownloadStore()
    @State var downloads = DownloadStore().library()

    /// A download removed because the reader finished it, and the bytes waiting in case
    /// they change their mind. `offline-downloads` gives them ten seconds.
    @State var removedDownload: RemovedDownload?

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

    /// Opens a publication the system handed over, or says why it cannot.
    ///
    /// Straight into the reader, per `local-library`: "the publication opens directly in
    /// the reader". No intermediate screen, because the reader already chose this file in
    /// another app and asking again would be asking twice.
    ///
    /// Remembered at the same time. The spec asks for the offer to be "once and
    /// unobtrusively", and a bookmark to the file the reader just chose to open is the
    /// least obtrusive form of it: nothing to dismiss, and the file is where they left it.
    private func openHandedOver(_ url: URL) async {
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
    private func dismissedReader() {
        refreshProgress(dismissed)
    }

    private func refreshProgress(_ closed: ReadingSelection?) {
        Task {
            await library.refreshProgress()
            await reportToKavita(closed?.publication)
        }
    }

    /// Tells the server where the reader got to, when the publication came from one.
    private func reportToKavita(_ publication: Publication?) async {
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
    private func openNext(_ publication: Publication) {
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
    private func show(_ place: QuickActionRequest) {
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
    private func keepForOffline(_ selection: ReadingSelection) async {
        guard let file = await keptForOffline(selection.url, into: downloadStore.directory) else { return }
        SmbReachability.clear()
        reading = ReadingSelection(publication: selection.publication, url: file)
        dismissed = reading
    }

    /// Returns both stores to what a fresh install has, and nothing more.
    ///
    /// Two stores, and only what each one calls a setting. The reading *defaults* are
    /// settings; a theme chosen while reading is not, and neither is progress.
    private func resetSettings() {
        settingsStore.reset()
        settings = settingsStore.settings()
        let reader = ReaderPreferences()
        reader.save(reader.themes().clearingDefaults())
    }

    /// Writes through on every change, so the theme above recomposes with it.
    private var settingsBinding: Binding<AppSettings> {
        Binding(
            get: { settings },
            set: { new in
                settings = new
                settingsStore.save(new)
            }
        )
    }

    var body: some Scene {
        WindowGroup {
            LibraryView(
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
                    onRemoveSource: { library.remove($0) },
                    onRenameSource: { library.rename($0, to: $1) },
                    onReorderSource: { library.move($0, to: $1) },
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
