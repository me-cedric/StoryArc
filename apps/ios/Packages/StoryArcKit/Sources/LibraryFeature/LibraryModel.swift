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
    public private(set) var scanState: LibraryScanState = .idle
    /// Folders the user has added, in the order they added them.
    public internal(set) var folders: [URL] = []

    /// Covers already decoded, keyed by publication id.
    ///
    /// `publication-formats` requires covers to be extracted as rows approach the
    /// viewport rather than during the scan, so this fills in as cells appear and
    /// never during `scan`.
    private var covers: [String: CGImage] = [:]
    /// Where each publication came from, so a cover can be loaded later.
    private var locations: [String: URL] = [:]
    private var scanTask: Task<Void, Never>?
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

    public init(
        progress: ProgressStore? = nil,
        bookmarks: FolderBookmarks? = nil,
        preferences: LibraryPreferences? = nil,
        sourceStore: SourceStore? = nil,
        shelvesStore: ShelvesStore? = nil
    ) {
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
    }

    /// Stops a running scan. `local-library` requires the scan to be cancellable.
    public func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
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

    private func scan(_ folder: URL) {
        scanTask?.cancel()
        scanState = .scanning(found: publications.count)

        scanTask = Task { [weak self] in
            // What this walk actually saw, so what it did not see can go afterwards.
            var seen: Set<String> = []
            for await event in LibraryScanner.scan(folderAt: folder) {
                guard let self, !Task.isCancelled else { return }
                switch event {
                case let .found(publication):
                    seen.insert(publication.id)
                    self.append(publication, in: folder)
                case .skipped:
                    // Counted in the finished event. Not surfaced per-file: a scan
                    // of a messy folder would otherwise be a wall of notices.
                    break
                case let .finished(found, skipped):
                    self.forgetVanished(under: folder, seen: seen)
                    self.scanState = .finished(found: found, skipped: skipped)
                    // Progress is loaded here rather than only when the view
                    // appears. The view appears before the scan produces anything,
                    // so a load at that point matches recorded positions against an
                    // empty library and the continue row never fills.
                    await self.refreshProgress()
                }
            }
        }
    }

    /// Drops what this folder no longer holds.
    ///
    /// `sources`: when a refresh shows a publication "is no longer present in the source",
    /// it "is removed from the library view and its reading progress is retained". The
    /// second half needs no code — progress lives in its own store, keyed by identity, and
    /// nothing here touches it, so a file that comes back finds its position waiting.
    ///
    /// Scoped to the folder that was walked. A scan of one source must not evict another
    /// source's titles just because it did not happen to see them, which is the mistake
    /// that turns a refresh into a library that empties one folder at a time.
    private func forgetVanished(under folder: URL, seen: Set<String>) {
        let gone = publications.filter { publication in
            guard !seen.contains(publication.id),
                  let location = locations[publication.id]
            else { return false }
            return location.path().hasPrefix(folder.path())
        }
        guard !gone.isEmpty else { return }

        let ids = Set(gone.map(\.id))
        publications.removeAll { ids.contains($0.id) }
        for id in ids {
            covers[id] = nil
            locations[id] = nil
        }
    }

    private func append(_ publication: Publication, in folder: URL) {
        // Attributed here rather than by the indexer: indexing decides what a publication
        // is, and the library is the only thing that knows which source it was reached
        // through. `sources` needs this for a source's item count, and
        // `library-browsing` for the order two sources holding one title appear in.
        var attributed = publication
        attributed.sourceID = source(of: folder)

        // A publication already present from another folder is not added twice.
        // Identity is what decides, not the path, so the same file reached two ways
        // is one row (ADR-0006).
        if let seen = publications.firstIndex(
            where: { $0.identity.matches(publication.identity) }
        ) {
            // Unless the second find knows something the first did not. The app's own
            // Documents folder is scanned before any source is restored, so a reader whose
            // library lives there had every publication found unattributed first — and a
            // source that holds eleven books reported nought. Whichever scan carries a
            // source wins; the earlier row is otherwise identical.
            if publications[seen].sourceID == nil, attributed.sourceID != nil {
                publications[seen].sourceID = attributed.sourceID
            }
            return
        }

        publications.append(attributed)
        if let path = publication.identity.normalizedPath {
            locations[publication.id] = URL(fileURLWithPath: path)
        }
        if case let .scanning(found) = scanState {
            scanState = .scanning(found: found + 1)
        }
        // ponytail: re-arranged in batches during a scan, not per publication —
        // sorting after every one of 10,000 appends is quadratic. The scan's own
        // completion rebuilds the rest, so the only visible effect is that the
        // last few rows arrive together.
        if publications.count % rebuildEvery == 0 { rebuild() }
    }

    private let rebuildEvery = 24

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

        // Disk before the archive. `sources` asks for a cover to be "stored on disk at
        // display resolution", and the reason is what this skips: without it every launch
        // reopened a ZIP, read its central directory, inflated an entry and decoded an
        // image, per cover, to draw a grid the reader had already seen.
        let cache = CoverCache()
        let identity = publication.id
        if let stored = await Task.detached(priority: .utility, operation: {
            cache.image(for: identity, maxPixelSize: maxPixelSize)
        }).value {
            covers[publication.id] = stored
            return stored
        }

        guard let url = locations[publication.id] else { return nil }

        let image = await Task.detached(priority: .utility) {
            let decoded = try? await CoverLoader.anyCover(
                for: publication, at: url, maxPixelSize: maxPixelSize
            )
            if let decoded { cache.store(decoded, for: identity, maxPixelSize: maxPixelSize) }
            return decoded
        }.value

        guard let image else { return nil }
        covers[publication.id] = image
        return image
    }
}
