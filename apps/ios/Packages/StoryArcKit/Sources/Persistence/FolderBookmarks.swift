public import Foundation

/// Folders the user has added, remembered across launches.
///
/// `local-library`: "the app stores a security-scoped bookmark and can re-open the
/// folder after a device restart without asking again". A plain path cannot do
/// that — the sandbox grants access to the *picked* URL, and that grant is what a
/// bookmark preserves.
///
/// `UserDefaults` rather than the SwiftData store: this is a handful of small
/// blobs read once at launch, and putting them in the progress database would mean
/// opening it before the first screen for no benefit.
/// Not `Sendable`: `UserDefaults` is not, and claiming otherwise would be a lie
/// the compiler cannot catch. It is cheap to construct where it is needed.
public struct FolderBookmarks {
    private let defaults: UserDefaults
    private let key = "app.storyarc.libraryFolders"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// A folder that could not be re-opened, and why.
    public struct Stale: Sendable, Equatable {
        /// The last known name, so the message can say *which* folder.
        ///
        /// `local-library` requires the explanation to name the folder — "a folder
        /// is no longer available" sends someone hunting through four of them.
        public let name: String
    }

    public struct Restored: Sendable {
        public let folders: [URL]
        /// Folders whose bookmarks no longer resolve: deleted, unmounted, or a
        /// permission the user revoked.
        public let stale: [Stale]
    }

    /// Remembers a folder. Adding one already remembered is a no-op.
    public func add(_ url: URL) throws {
        var stored = raw()
        let bookmark = try url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let name = url.lastPathComponent
        guard !stored.contains(where: { $0.name == name && $0.data == bookmark }) else { return }
        stored.append(Entry(name: name, data: bookmark))
        write(stored)
    }

    /// Every folder still reachable, plus the ones that are not.
    ///
    /// Resolving *starts* the security-scoped access and deliberately does not stop
    /// it: the library reads pages out of these folders for as long as it is open,
    /// and balancing the call here would revoke access before the first cover loads.
    public func restore() -> Restored {
        var folders: [URL] = []
        var stale: [Stale] = []
        var survivors: [Entry] = []

        for entry in raw() {
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: entry.data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                stale.append(Stale(name: entry.name))
                continue
            }
            guard url.startAccessingSecurityScopedResource() else {
                // Resolvable but not accessible: the grant is gone even though the
                // path is still valid, which is what a revoked permission looks
                // like. Reported rather than silently dropped, because
                // `local-library` requires a single action to re-pick it.
                stale.append(Stale(name: entry.name))
                continue
            }
            folders.append(url)
            // A stale bookmark still resolved, so it is refreshed rather than
            // reported: the folder moved and the system found it anyway.
            if isStale, let refreshed = try? url.bookmarkData(options: .minimalBookmark) {
                survivors.append(Entry(name: url.lastPathComponent, data: refreshed))
            } else {
                survivors.append(entry)
            }
        }

        // Unresolvable entries are dropped, so a folder that has gone for good does
        // not report itself every launch for ever.
        if survivors.count != raw().count { write(survivors) }
        return Restored(folders: folders, stale: stale)
    }

    /// Forgets a folder. Reading progress for what was inside it is untouched —
    /// ADR-0006 keys progress on the publication, not on the folder it came from.
    public func remove(named name: String) {
        write(raw().filter { $0.name != name })
    }

    public func removeAll() {
        defaults.removeObject(forKey: key)
    }

    // MARK: - Storage

    private struct Entry: Codable {
        let name: String
        let data: Data
    }

    private func raw() -> [Entry] {
        guard let data = defaults.data(forKey: key),
              let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        return entries
    }

    private func write(_ entries: [Entry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: key)
    }
}
