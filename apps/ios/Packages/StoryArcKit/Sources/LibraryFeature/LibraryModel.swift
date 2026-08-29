public import Foundation

public import CoreGraphics
internal import Formats
public import Persistence
public import StoryArcCore

/// What the library is doing, so the UI can say so rather than guess.
public enum LibraryScanState: Sendable, Equatable {
    case idle
    /// A scan is running. The count is what `local-library` asks to be reported.
    case scanning(found: Int)
    case finished(found: Int, skipped: Int)
    /// The folder could not be read — most often a permission that went stale.
    case failed(reason: String)
}

/// The library's state and the work behind it.
///
/// `local-library` requires a scan that reports progress, does not block browsing
/// what it has already found, and is cancellable. So publications are appended as
/// the scanner emits them and the view redraws each time, rather than waiting for
/// a finished list.
///
/// `@MainActor` because everything here is view state. The scanning and decoding
/// happen off it — the model only ever receives results.
@MainActor
@Observable
public final class LibraryModel {
    public internal(set) var publications: [Publication] = []

    /// What the user is looking at. Setting it re-arranges the shelf.
    public var query = LibraryQuery() {
        didSet {
            guard query != oldValue else { return }
            preferences?.save(query)
            rebuild()
        }
    }

    /// Grid or list. `library-browsing` requires both, and requires the choice to
    /// persist.
    public var layout: LibraryLayout = .grid {
        didSet { if layout != oldValue { preferences?.save(layout) } }
    }

    /// The publications on screen: filtered, ranked and sorted.
    ///
    /// Stored rather than computed. `library-browsing` requires a library of
    /// 10,000 to stay usable, and a computed property would re-sort all of them
    /// on every redraw.
    public private(set) var visible: [Publication] = []

    /// In-progress publications, most recently read first. Empty means the row is
    /// not drawn at all, which is what `library-browsing` asks for.
    public private(set) var continueReading: [Publication] = []
    // `internal(set)`, not `private(set)`: the scanning half of this type lives in
    // another file, and `private` is file-scoped.
    public internal(set) var scanState: LibraryScanState = .idle
    /// Folders the user has added, in the order they added them.
    public internal(set) var folders: [URL] = []

    /// Covers already decoded, keyed by publication id.
    ///
    /// `publication-formats` requires covers to be extracted as rows approach the
    /// viewport rather than during the scan, so this fills in as cells appear and
    /// never during `scan`.
    private var covers: [String: CGImage] = [:]
    // Internal, not private: the imported copies half of this type lives in another file.
    /// Where each publication came from, so a cover can be loaded later.
    var locations: [String: URL] = [:]
    // Internal, not private: the scanning half of this type lives in another file.
    var scanTask: Task<Void, Never>?

    /// The folder being walked, and what has been indexed in it so far.
    ///
    /// Held so an interrupted scan can be written down and picked up. `local-library`
    /// requires a scan to be "cancellable and resumable", which are one promise: a reader
    /// who stops a scan and starts it again should not wait for the same archives twice.
    var scanningFolder: URL?
    var scanned: [Publication] = []
    let journal: ScanJournal?

    // Internal, not private: the watching half of this type lives in another file.
    /// What each watched folder held when it was last looked at, keyed by the folder's path.
    ///
    /// In memory rather than on disk. `local-library` asks for a change made while the app
    /// was away to be reconciled cheaply, and a launch has nothing to reconcile *against* —
    /// the publications themselves are not cached either, so a snapshot read from disk would
    /// describe a library this process has not built yet.
    var snapshots: [String: FolderSnapshot] = [:]
    let watcher = FolderWatcher()

    let progressStore: ProgressStore?

    /// The reading lists every known Kavita server holds, once they have been asked.
    var serverLists: [ServerShelf] = []
    // Internal, not private: the shelves half of this type lives in another file.
    /// How far through each publication the reader got, keyed by publication id.
    var progress: [String: ReadingProgress] = [:]

    let bookmarks: FolderBookmarks?
    /// Folders that were remembered and can no longer be reached.
    ///
    /// `local-library` requires naming the folder and offering a single action to
    /// re-pick it, so the names are kept rather than the count.
    public private(set) var unavailableFolders: [String] = []

    private let preferences: LibraryPreferences?

    /// The configured sources, in the reader's own order.
    ///
    /// `sources` requires a registry, and until now the only thing that existed was the
    /// value type. A folder is a source: the library's source list was passed an empty
    /// array by both app shells, so it never drew a row for the folder a reader had
    /// picked.
    public internal(set) var registry = SourceRegistry()

    /// The reader's collections and reading lists.
    public internal(set) var shelves = Shelves()

    let sourceStore: SourceStore?
    let shelvesStore: ShelvesStore?

    /// Where copies the reader imported live. `local-library` asks for them to be kept in
    /// "app-managed storage", and this store already owns exactly that — see
    /// ``ImportedCopies``.
    let downloadStore: DownloadStore?

    /// The last import that did not happen, named so the reader can be told which file.
    ///
    /// `local-library` forbids a generic failure elsewhere and there is no reason an import
    /// should be the exception: a reader who picked the wrong file needs to know it was the
    /// file rather than the app.
    public var importFailure: String?

    public init(
        progress: ProgressStore? = nil,
        bookmarks: FolderBookmarks? = nil,
        preferences: LibraryPreferences? = nil,
        sourceStore: SourceStore? = nil,
        shelvesStore: ShelvesStore? = nil,
        downloadStore: DownloadStore? = nil,
        journal: ScanJournal? = nil
    ) {
        self.journal = journal
        self.downloadStore = downloadStore
        self.sourceStore = sourceStore
        self.shelvesStore = shelvesStore
        shelves = shelvesStore?.shelves() ?? Shelves()
        self.registry = sourceStore?.registry() ?? SourceRegistry()
        self.progressStore = progress
        self.bookmarks = bookmarks
        self.preferences = preferences
        // Property observers do not run during initialisation, so restoring here
        // cannot loop back into the save that the observers perform.
        if let preferences {
            self.query = preferences.query()
            self.layout = preferences.layout()
        }
    }

    /// Re-opens the folders from a previous launch and scans them.
    ///
    /// `local-library`: a picked folder is reachable again "after a device restart
    /// without asking again". Called once, when the library first appears.
    public func restoreFolders() {
        guard folders.isEmpty else { return }
        if let bookmarks {
            let restored = bookmarks.restore()
            unavailableFolders = restored.stale.map(\.name)
            for folder in restored.folders {
                folders.append(folder)
                register(folder)
                scan(folder)
            }
            startWatching()
        }
        if folders.isEmpty { scan(documentsFolder) }
    }

    /// The app's own Documents directory.
    ///
    /// Not a library the user picked — it is where a file shared to StoryArc or
    /// copied in through Files lands. `sources` promises the app "works without
    /// any setup", and dropping a comic into the app's folder and finding it there
    /// is what that means on iOS. Android scans `getExternalFilesDir` for the same
    /// reason. It is scanned, deliberately not added to `folders`: there is no
    /// bookmark to keep and nothing for the user to remove.
    private var documentsFolder: URL {
        URL.documentsDirectory
    }

    /// The fraction read, for a cover's progress indicator.
    ///
    /// `nil` for a publication never opened — `library-browsing` wants an
    /// indicator on a *partially read* cover, and a ring at zero on every unread
    /// book would be noise rather than information.
    public func readFraction(of publication: Publication) -> Double? {
        guard let record = progress[publication.id] else { return nil }
        if record.isFinished { return 1 }
        let fraction = record.position.fraction
        return fraction > 0 ? fraction : nil
    }

    /// Reloads recorded positions. Called when the library appears, so returning
    /// from the reader shows the page you reached.
    public func refreshProgress() async {
        guard let progressStore else { return }
        guard let records = try? await progressStore.recent(limit: 500) else { return }
        var byID: [String: ReadingProgress] = [:]
        for publication in publications {
            if let match = records.first(where: { $0.identity.matches(publication.identity) }) {
                byID[publication.id] = match
            }
        }
        progress = byID
        rebuild()
    }

    /// Adds a folder and scans it.
    ///
    /// The security-scoped access is started here and deliberately not stopped:
    /// the library keeps reading pages out of these files for as long as it is on
    /// screen, and balancing the call on return would revoke access before the
    /// first cover loads.
    public func addFolder(_ url: URL) {
        guard !folders.contains(url) else { return }
        folders.append(url)
        _ = url.startAccessingSecurityScopedResource()
        // Remembered before the scan, so a folder added and then immediately
        // backgrounded is still there next launch.
        try? bookmarks?.add(url)
        register(url)
        scan(url)
        startWatching()
    }

    /// Stops a running scan. `local-library` requires the scan to be cancellable.
    public func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        // Written down rather than lost, which is what makes the next scan of this folder a
        // resumption instead of a repetition.
        if let scanningFolder { journal?.record(scanned, inFolder: scanningFolder.path) }
        if case .scanning(let found) = scanState {
            scanState = .finished(found: found, skipped: 0)
        }
    }

    /// Forgets everything. Used when a folder is removed, and by previews.
    public func reset() {
        cancelScan()
        publications = []
        visible = []
        continueReading = []
        covers = [:]
        locations = [:]
        folders = []
        scanState = .idle
    }

    // Internal, not private: the scanning half of this type lives in another file.
    let rebuildEvery = 24

    // Internal, not private: `private` is file-scoped, and the callers now sit
    // in the other half of this type.
    /// Recomputes what is on screen from the library and the query.
    func rebuild() {
        visible = LibraryIndex.arrange(publications, query: query) { self.state(of: $0) }
        continueReading = LibraryIndex.continueReading(publications) { self.state(of: $0) }
    }

    private func state(of publication: Publication) -> LibraryIndex.Progress {
        .of(progress[publication.id])
    }

    /// Clears every filter, keeping the search and the sort.
    ///
    /// `library-browsing`: an empty-looking library must say filters are active
    /// and offer one action to clear them. This is that action.
    public func clearFilters() {
        query.readStates = []
        query.formats = []
        query.languages = []
    }

    /// Formats actually present, so the filter never offers one that would empty
    /// the library.
    public var availableFormats: [PublicationFormat] {
        Array(Set(publications.map(\.format))).sorted { $0.displayName < $1.displayName }
    }

    /// Where a publication's file is, so the app layer can hand it to a reader.
    public func location(of publication: Publication) -> URL? {
        locations[publication.id]
    }

    // MARK: - Covers

    /// The cover for a publication, decoded once and remembered.
    ///
    /// Called by a cell as it appears, which is what makes extraction lazy. A
    /// publication with no cover returns `nil` rather than throwing: a missing
    /// cover is a normal state and the cell draws a placeholder.
    public func cover(for publication: Publication, maxPixelSize: Int) async -> CGImage? {
        if let cached = covers[publication.id] { return cached }
        guard let url = locations[publication.id] else { return nil }

        let image = await Task.detached(priority: .utility) {
            try? await CoverLoader.anyCover(
                for: publication, at: url, maxPixelSize: maxPixelSize
            )
        }.value

        guard let image else { return nil }
        covers[publication.id] = image
        return image
    }
}
