import AppKit
import LibraryFeature
import Persistence
import StoryArcCore

/// The Mac's composition root for the library: StoryArcKit's `LibraryModel` and the Mac
/// system hooks around it.
///
/// The model, its queries, the progress store and the format layer are the package's; what
/// is Mac here is the sandbox-correct folder access (`MacFolderBookmarks`), the folder
/// sources' states, files handed over by the system, the recent list and the watcher. The
/// iOS shell holds the same wiring in `StoryArcApp.swift`; this is its Mac copy until parent
/// task 5.12 shares it.
@MainActor
@Observable
final class MacLibrary {
    let model: LibraryModel
    let progress: ProgressStore?
    let bookmarks: MacFolderBookmarks
    let recents = RecentPublications()
    let watcher = MacFolderWatcher()
    /// The configured servers and the sheets that add them. Wave 3.
    let servers: MacSources
    /// The download queue and the metered rule over it. Wave 3.
    let downloads: MacDownloads
    /// Library sync at start and at quit. Wave 3.
    let sync: MacSync
    /// What the app keeps on this Mac, store by store. Wave 3.
    let storage: MacStorage

    /// Every folder the reader chose, with its state. Grey ones keep their place.
    private(set) var sources: [FolderSource] = []
    /// Files the system handed over that would not open, named with the reason.
    private(set) var refused: [RefusedFile] = []
    /// What a `storyarc://` link named that the app does not hold, said in grey. Task 5.8.
    private(set) var linksNotFound: [String] = []
    /// Dropped files past the window limit, listed so the reader can open them from here.
    private(set) var listedForLater: [ReaderTarget] = []
    /// Reader windows the last run had open that could not come back.
    private(set) var couldNotRestore: [ReaderTarget] = []
    /// A folder dropped on the library, waiting for the reader to agree to add it.
    var offeredFolder: URL?
    /// Where something outside the library window asked it to go: the Dock menu, or a walk.
    var navigationRequest: LibraryNavigation?
    /// A *Start from the Beginning* waiting for the reader to confirm it.
    var restartRequest: RestartRequest?
    /// The reading record of each publication on the shelf, keyed by publication id.
    ///
    /// A Mac-side copy of `LibraryModel.record(of:)`, which is internal to `LibraryFeature`:
    /// Home and the detail page need the record, not only the fraction, and making the
    /// package's accessor public is a parent edit under `apps/ios` (task 1.30's family).
    private(set) var records: [String: ReadingProgress] = [:]

    private var accesses: [String: FolderAccess] = [:]
    private var mountObserver: (any NSObjectProtocol)?

    /// The library the running app made, for the walks and captures hosted in it.
    private(set) static weak var live: MacLibrary?

    init(bookmarks: MacFolderBookmarks = MacFolderBookmarks()) {
        let store = try? ProgressStore()
        progress = store
        self.bookmarks = bookmarks
        model = LibraryModel(
            progress: store,
            // The iOS bookmark store mints minimal bookmarks, which the sandbox refuses on
            // the next launch; `MacFolderBookmarks` holds the folders instead.
            bookmarks: nil,
            preferences: LibraryPreferences(),
            sourceStore: SourceStore(),
            shelvesStore: ShelvesStore(),
            downloadStore: DownloadStore(),
            journal: ScanJournal()
        )
        servers = MacSources(model: model)
        downloads = MacDownloads()
        sync = MacSync(runner: MacSyncWiring.runner(progress: store)) {
            await MacSyncWiring.latestChange(in: store)
        }
        storage = MacStorageWiring.storage(progress: store, queue: downloads.queue)
        Self.live = self
    }

    // MARK: - Launch

    /// Puts back what the last run had: the folders, the progress a failed write left
    /// behind, and the reader windows that can be reopened.
    func restore() async {
        if let progress { await ProgressWriter.retryPending(into: progress) }
        let restored = bookmarks.restore()
        for access in restored.folders {
            accesses[access.key] = access
            model.addFolder(access.url)
        }
        sources = FolderSourceStates.resolve(
            folders: restored.folders.map { RememberedFolder(key: $0.key, name: $0.name, url: $0.url) },
            stale: restored.stale.map(\.name),
            isReachable: Self.isReachable
        )
        watchVolumes()
        startWatching()
        // Each `addFolder` starts a walk that the next one cancels; one rescan walks them all.
        if restored.folders.count > 1 { await model.rescan() }
        // The servers join the shelf beside the folders, as on a phone, and what was downloaded
        // joins it too; what the last quit paused carries on (`desktop-experience`).
        await model.readServers()
        await model.adoptDownloads()
        downloads.resumeAfterLaunch()
        await refreshProgress()
    }

    // MARK: - Progress

    /// Reloads the recorded positions into the model and into ``records``.
    func refreshProgress() async {
        await model.refreshProgress()
        guard let progress, let recent = try? await progress.recent(limit: 500) else { return }
        records = Self.match(recent, to: model.publications)
    }

    /// The record for a publication, if it was ever opened.
    func record(of publication: Publication) -> ReadingProgress? {
        records[publication.id]
    }

    /// Pairs stored records with the publications on the shelf, by identity, as
    /// `LibraryModel.refreshProgress()` does.
    static func match(_ recent: [ReadingProgress], to publications: [Publication]) -> [String: ReadingProgress] {
        var byID: [String: ReadingProgress] = [:]
        for publication in publications {
            if let match = recent.first(where: { $0.identity.matches(publication.identity) }) {
                byID[publication.id] = match
            }
        }
        return byID
    }

    /// The saved reader windows this launch can reopen. The rest are named in the library.
    func restorableReaders() -> [ReaderSession] {
        let plan = RestorationPlan.plan(saved: ReaderWindows.shared.savedSessions()) { Self.isReachable($0.url) }
        couldNotRestore = plan.missing
        return plan.reopen
    }

    // MARK: - Folders

    /// Adds a folder the reader chose in the system's own chooser.
    func addFolder(_ url: URL) {
        do {
            try bookmarks.add(url)
        } catch {
            refused.append(RefusedFile(name: url.lastPathComponent, outcome: .unreadable))
            return
        }
        // The chooser's grant lasts the session; the bookmark is what survives it.
        let restored = bookmarks.restore()
        for access in restored.folders where accesses[access.key] == nil {
            accesses[access.key] = access
        }
        sources = FolderSourceStates.resolve(
            folders: restored.folders.map { RememberedFolder(key: $0.key, name: $0.name, url: $0.url) },
            stale: restored.stale.map(\.name),
            isReachable: Self.isReachable
        )
        model.addFolder(url)
        startWatching()
    }

    /// Forgets a folder. Reading progress is untouched (ADR-0006).
    func removeFolder(_ source: FolderSource) {
        bookmarks.remove(key: source.key)
        accesses[source.key]?.end()
        accesses[source.key] = nil
        sources.removeAll { $0.key == source.key }
        if let url = source.url,
           let folderSource = model.registry.sources.first(where: { $0.locator == url.path(percentEncoded: false) }) {
            model.remove(folderSource, credentials: nil)
        }
        startWatching()
    }

    /// The one action a grey source offers: choose the folder again.
    func repick(_ source: FolderSource) {
        if source.state == .needsAccess { bookmarks.remove(key: source.key) }
        sources.removeAll { $0.key == source.key }
        chooseFolder()
    }

    /// The system's folder chooser, from the menu or a grey source.
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "desktop.chooser.addFolder")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        addFolder(url)
    }

    /// The system's file chooser, from File > Open File.
    func chooseFile() async -> [ReaderTarget] {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = MacDocumentTypes.readable
        guard panel.runModal() == .OK else { return [] }
        return await open(panel.urls)
    }

    static func isReachable(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    private func startWatching() {
        let folders = sources.filter { $0.state == .available }.compactMap(\.url)
        watcher.watch(folders) { [weak self] in await self?.model.reconcileWatchedFolders() }
    }

    /// *A folder on an unmounted volume* returns by itself when the volume does.
    private func watchVolumes() {
        guard mountObserver == nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        mountObserver = center.addObserver(
            forName: NSWorkspace.didMountNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.volumesChanged() }
        }
        _ = center.addObserver(
            forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.volumesChanged() }
        }
    }

    private func volumesChanged() {
        let before = sources
        sources = FolderSourceStates.revisited(sources, isReachable: Self.isReachable)
        for (was, now) in zip(before, sources) where was.state == .offline && now.state == .available {
            if let url = now.url { model.addFolder(url) }
        }
        startWatching()
    }

    // MARK: - Files handed over

    /// Opens files from Finder, a drop, the Dock or the command line: each readable one up
    /// to the limit becomes a reader target, the rest are listed, and refusals are named.
    func open(_ urls: [URL]) async -> [ReaderTarget] {
        let (files, folders) = OpenBatch.split(urls)
        if let folder = folders.first { offeredFolder = folder }
        let plan = OpenBatch.plan(files)
        var targets: [ReaderTarget] = []
        for url in plan.open {
            switch await MacOpenedFile.index(url) {
            case let .opened(publication):
                let target = ReaderTarget(publication: publication, url: url)
                targets.append(target)
                NSDocumentController.shared.noteNewRecentDocumentURL(url)
            case let outcome:
                refused.append(RefusedFile(name: url.lastPathComponent, outcome: outcome))
            }
        }
        for url in plan.listed {
            if case let .opened(publication) = await MacOpenedFile.index(url) {
                listedForLater.append(ReaderTarget(publication: publication, url: url))
            } else {
                refused.append(RefusedFile(name: url.lastPathComponent, outcome: .unreadable))
            }
        }
        return targets
    }

    /// Opens whatever the system or a drop handed over, in reader windows.
    ///
    /// Any window may call this: the inbox empties on the first take, so a drop on a reader
    /// while the library window is closed still opens, and two windows never open it twice.
    func openHandedOver(using openReader: (ReaderTarget) -> Void) async {
        let handed = FileInbox.shared.take()
        let links = handed.filter { StoryArcLink.isLink($0.absoluteString) }
        for link in links { follow(link, using: openReader) }
        let urls = handed.filter { !StoryArcLink.isLink($0.absoluteString) }
        guard !urls.isEmpty else { return }
        for target in await open(urls) {
            recents.note(target)
            openReader(target)
        }
    }

    /// A publication on the shelf, as a reader target, or `nil` when its file is not here.
    func target(for publication: Publication) -> ReaderTarget? {
        guard let url = model.location(of: publication) else { return nil }
        return ReaderTarget(publication: publication, url: url)
    }

    /// Queues a catalogue row the reader asked to download, by hand.
    ///
    /// - Returns: false when the row's entry could not be found in its catalogue.
    /// `byHand` is false for a bulk download, which the metered rule may hold back.
    @discardableResult
    func download(_ publication: Publication, byHand: Bool = true) async -> Bool {
        guard let found = await RemoteEntry.resolve(
            publication, in: model.registry, credentials: servers.credentials
        ) else { return false }
        downloads.enqueue(found.entry, using: found.acquisition, sourceID: found.sourceID, byHand: byHand)
        return true
    }

    /// The diagnostic as the preferences export it, redacted (task 3.14).
    func diagnosticText() async -> String {
        let history = await progress?.sizeOnDisk() ?? 0
        return MacDiagnostic.text(
            settings: MacSettings.shared.settings, sources: model.registry,
            cacheBytes: StorageUsage().cacheBytes(), historyBytes: history,
            extra: [
                "connection = \(downloads.monitor.condition)",
                "downloadsPending = \(downloads.pending.count)",
                "downloadsHeldOnMeteredLink = \(downloads.held.count)",
                "sync = \(sync.runner.map { String(describing: $0.status) } ?? "unavailable")",
            ]
        )
    }

    /// Everything StoryArc keeps on this Mac, removed: the way to leave nothing behind before
    /// the system's own uninstall (`desktop-experience`, *Removing the app*). Confirmed first.
    func removeAllData() async {
        for store in MacStorage.Store.allCases { await storage.clear(store) }
        for source in servers.servers { servers.remove(source.id) }
        for folder in sources { removeFolder(folder) }
        recents.clear()
        NSDocumentController.shared.clearRecentDocuments(nil)
        MacSettings.shared.reset()
        await refreshProgress()
    }

    func dismissRefused() { refused = [] }

    func dismissLinksNotFound() { linksNotFound = [] }

    /// Acts on one `storyarc://` link: a publication opens, a source shows its tab in
    /// Preferences, an unknown name is said in grey, and anything else changes nothing.
    func follow(_ link: URL, using openReader: (ReaderTarget) -> Void) {
        switch StoryArcLink.resolve(link, publications: model.publications, sources: model.registry.sources) {
        case let .open(publication):
            guard let target = target(for: publication) else { return linksNotFound.append(publication.displayTitle) }
            recents.note(target)
            openReader(target)
        case .showSource:
            navigationRequest = .sources
        case let .notFound(name):
            if !linksNotFound.contains(name) { linksNotFound.append(name) }
        case .refused:
            break
        }
    }

    func dismissListed() { listedForLater = [] }

    func dismissCouldNotRestore() { couldNotRestore = [] }
}
