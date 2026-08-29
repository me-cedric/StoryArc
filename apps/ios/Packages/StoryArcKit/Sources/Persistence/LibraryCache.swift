public import Foundation

public import StoryArcCore

/// The library as it was last seen, so opening the app does not mean walking every folder
/// before anything appears.
///
/// `sources`: the catalogue is cached "so the library opens instantly and stays browsable
/// while offline", and a refresh "updates the view incrementally rather than clearing it
/// and re-populating". This is the first half. The second is the scan, which appends to
/// what this restored and removes only what it can prove is gone.
///
/// In the caches directory, deliberately. Losing this costs a rescan and nothing else —
/// no reading position, no download, no source — so it is exactly the kind of thing the
/// system should be free to reclaim, and the kind of thing the Privacy screen's "Clear
/// cache" should take with it. Covers live beside it for the same reason.
///
/// One file rather than a row per publication. The whole library is read at once to draw
/// one screen, and a store that read it a row at a time would let two halves of the same
/// snapshot disagree — the same argument `SourceStore` makes for the registry.
///
/// Android's `LibraryCache` writes the same shape.
public struct LibraryCache: Sendable {

    /// What was on the shelf, and when it was last confirmed.
    public struct Snapshot: Codable, Sendable, Equatable {
        /// When a scan last completed. What the "cached, last refreshed…" indicator states.
        public let refreshedAt: Date
        public let publications: [Publication]
        /// Where each publication was, keyed by its stable id.
        ///
        /// Paths rather than bookmarks: this is a cache, and a path that no longer resolves
        /// is a publication the next scan will not find and will remove. A stale bookmark
        /// would be the same thing with more ceremony.
        public let locations: [String: String]

        public init(refreshedAt: Date, publications: [Publication], locations: [String: String]) {
            self.refreshedAt = refreshedAt
            self.publications = publications
            self.locations = locations
        }
    }

    private let file: URL

    public init(directory: URL? = nil) {
        let base = directory ?? URL.cachesDirectory
        file = base.appending(path: "library.json")
    }

    /// The last snapshot, or `nil` when there is none this build can read.
    ///
    /// A snapshot written by a newer version is discarded rather than guessed at. It costs
    /// one rescan, which is what a cache miss is supposed to cost.
    public func read() -> Snapshot? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    /// Writes the snapshot, replacing whatever was there.
    ///
    /// Failure is silent and correct: this is a cache. A device with no room left should
    /// show the library, not refuse to.
    public func write(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: file, options: .atomic)
    }

    /// Forgets the shelf. The Privacy screen's "Clear cache", and the tests.
    public func clear() {
        try? FileManager.default.removeItem(at: file)
    }
}
