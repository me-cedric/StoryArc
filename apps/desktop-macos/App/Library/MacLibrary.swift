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

    /// Every folder the reader chose, with its state. Grey ones keep their place.
    private(set) var sources: [FolderSource] = []
    /// Files the system handed over that would not open, named with the reason.
    private(set) var refused: [RefusedFile] = []
    /// Dropped files past the window limit, listed so the reader can open them from here.
    private(set) var listedForLater: [ReaderTarget] = []
    /// Reader windows the last run had open that could not come back.
    private(set) var couldNotRestore: [ReaderTarget] = []
    /// A folder dropped on the library, waiting for the reader to agree to add it.
    var offeredFolder: URL?
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
        let urls = FileInbox.shared.take()
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

    func dismissRefused() { refused = [] }

    func dismissListed() { listedForLater = [] }

    func dismissCouldNotRestore() { couldNotRestore = [] }
}
