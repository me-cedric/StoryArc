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
    public private(set) var publications: [Publication] = []

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
    public private(set) var folders: [URL] = []

    /// Covers already decoded, keyed by publication id.
    ///
    /// `publication-formats` requires covers to be extracted as rows approach the
    /// viewport rather than during the scan, so this fills in as cells appear and
    /// never during `scan`.
    private var covers: [String: CGImage] = [:]
    /// Where each publication came from, so a cover can be loaded later.
    private var locations: [String: URL] = [:]
    private var scanTask: Task<Void, Never>?
    private let progressStore: ProgressStore?
    /// How far through each publication the reader got, keyed by publication id.
    private var progress: [String: ReadingProgress] = [:]

    private let bookmarks: FolderBookmarks?
    /// Folders that were remembered and can no longer be reached.
    ///
    /// `local-library` requires naming the folder and offering a single action to
    /// re-pick it, so the names are kept rather than the count.
    public private(set) var unavailableFolders: [String] = []

    private let preferences: LibraryPreferences?

    public init(
        progress: ProgressStore? = nil,
        bookmarks: FolderBookmarks? = nil,
        preferences: LibraryPreferences? = nil
    ) {
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
            for await event in LibraryScanner.scan(folderAt: folder) {
                guard let self, !Task.isCancelled else { return }
                switch event {
                case let .found(publication):
                    self.append(publication, in: folder)
                case .skipped:
                    // Counted in the finished event. Not surfaced per-file: a scan
                    // of a messy folder would otherwise be a wall of notices.
                    break
                case let .finished(found, skipped):
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

    private func append(_ publication: Publication, in folder: URL) {
        // A publication already present from another folder is not added twice.
        // Identity is what decides, not the path, so the same file reached two ways
        // is one row (ADR-0006).
        guard !publications.contains(where: { $0.identity.matches(publication.identity) })
        else { return }

        publications.append(publication)
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

    /// Recomputes what is on screen from the library and the query.
    private func rebuild() {
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
