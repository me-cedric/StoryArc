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

    @State private var settings = SettingsStore().settings()
    private let settingsStore = SettingsStore()

    @State private var isShowingSettings = false

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
    private let progress: ProgressStore?

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
    private let downloadStore = DownloadStore()
    @State private var downloads = DownloadStore().library()

    /// A download removed because the reader finished it, and the bytes waiting in case
    /// they change their mind. `offline-downloads` gives them ten seconds.
    @State private var removedDownload: RemovedDownload?

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
                // The same store the downloads use — see `ImportedCopies` for why.
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

    /// The reading preset the appearance dictates, when the reader opted into that.
    ///
    /// `nil` when they have not, which leaves each shelf's own theme in force. Resolved
    /// here because "System" is a question about the device and this is where the answer
    /// is: `colorScheme` follows it whatever the setting says.
    private var linkedPreset: ThemePreset? {
        guard settings.linkReadingThemeToAppearance else { return nil }
        let resolved: AppearanceMode = settings.appearance == .system
            ? (colorScheme == .dark ? .dark : .light)
            : settings.appearance
        return .matching(resolved)
    }

    /// Reopens the publication from a copy the network cannot take away.
    ///
    /// The copying lives in `KeepForOffline.swift`, beside Android's own file of that
    /// name; what belongs here is only which publication the reader is then looking at.
    private func keepForOffline(_ selection: ReadingSelection) async {
        guard let file = await keptForOffline(selection.url, into: downloadStore.directory) else { return }
        SmbReachability.clear()
        reading = ReadingSelection(publication: selection.publication, url: file)
        dismissed = reading
    }

    /// Takes a finished publication's download off the device, reversibly.
    private func sweepFinishedDownload() async {
        let library = downloadStore.library()

        // Asked of the store one path at a time, and awaited: `ProgressStore` is an actor,
        // and a predicate that could not await it would answer "not finished" to everything
        // and sweep nothing, for ever, silently.
        var done: Set<String> = []
        for download in library.finished {
            let path = downloadStore.location(of: download).path
            let record = try? await progress?.progress(
                for: PublicationIdentity(normalizedPath: path)
            )
            if record?.isFinished == true { done.insert(path) }
        }

        let finished = downloadStore.finishedDownload(in: library) { done.contains($0) }
        guard let finished,
              let outcome = downloadStore.removeAfterFinishing(finished.id, from: library)
        else { return }

        downloads = outcome.library
        removedDownload?.settle()
        removedDownload = outcome.removed

        let taken = outcome.removed
        Task {
            try? await Task.sleep(for: .seconds(10))
            guard removedDownload?.download.id == taken.download.id else { return }
            taken.settle()
            removedDownload = nil
        }
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
                    isShowingSettings = true
                }
            )
            .storyArcTheme(appearance: settings.appearance)
            .speaking(settings.language)
            .sheet(isPresented: $isShowingSettings) {
                SettingsView(
                    settings: settingsBinding,
                    readerStore: ReaderPreferences(),
                    onReset: resetSettings,
                    sources: library.registry.sources,
                    itemCount: { library.itemCount(of: $0) },
                    onRemoveSource: { library.remove($0) },
                    onRenameSource: { library.rename($0, to: $1) },
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
            .alert(
                Text(verbatim: "Cannot open this file"),
                isPresented: Binding(
                    get: { refusedFile != nil },
                    set: { if !$0 { refusedFile = nil } }
                )
            ) {
                Button(role: .cancel) { refusedFile = nil } label: { Text(verbatim: "OK") }
            } message: {
                Text(refusedFile?.message ?? "")
            }
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
                        linkedPreset: linkedPreset
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
                        // `comic-reader`: the end of one volume offers the next. The app
                        // layer answers this because it is the only place that can see both
                        // the reader and the library — and the library is what knows a
                        // reading list may have a different opinion about what comes next.
                        nextInSeries: library.next(after: selection.publication),
                        onOpenNext: openNext,
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

/// One publication, chosen for reading.
private struct ReadingSelection: Identifiable {
    let publication: Publication
    let url: URL

    var id: String { publication.id }
}
