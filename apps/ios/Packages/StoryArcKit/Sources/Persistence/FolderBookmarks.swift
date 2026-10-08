public import Foundation

/// The places the app was granted access to, remembered across launches.
///
/// `local-library`: "the app stores a security-scoped bookmark and can re-open the
/// folder after a device restart without asking again". A plain path cannot do
/// that — the sandbox grants access to the *picked* URL, and that grant is what a
/// bookmark preserves.
///
/// Two kinds of place, one store, because a bookmark is a bookmark: folders the reader
/// picked, and single files another app handed over. ``Restored`` keeps them apart, and
/// keeping them apart is the whole point — a file filed among the folders became a
/// local-folder source named after the comic, whose walk listed nothing.
///
/// `UserDefaults` rather than the SwiftData store: this is a handful of small
/// blobs read once at launch, and putting them in the progress database would mean
/// opening it before the first screen for no benefit.
/// Not `Sendable`: `UserDefaults` is not, and claiming otherwise would be a lie
/// the compiler cannot catch. It is cheap to construct where it is needed.
public struct FolderBookmarks {
    private let defaults: UserDefaults
    private let key: String
    /// Resolved keys, so a scan asking for the same folder's identity once per publication
    /// costs one `bookmarkData` call rather than one per file. A class, not a dictionary
    /// stored directly: copying this struct must still see what an earlier copy resolved.
    private let cache = KeyCache()
    private final class KeyCache { var keys: [URL: String] = [:] }

    /// - Parameter key: where the bookmarks are kept. The library's folders use the default.
    ///   `library-sync` task 2.3 keeps the sync folder under a key of its own, so the sync
    ///   folder is never read as a library folder.
    public init(defaults: UserDefaults = .standard, key: String = "app.storyarc.libraryFolders") {
        self.defaults = defaults
        self.key = key
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
        /// Single publications another app handed over, in the order they arrived.
        ///
        /// Separate from ``folders`` rather than merged into it: a folder is a library the
        /// reader configured — it is a source, it is watched, it can be removed — and a
        /// handed-over file is none of those things. It is one book.
        public let files: [URL]
        /// Folders whose bookmarks no longer resolve: deleted, unmounted, or a
        /// permission the user revoked.
        public let stale: [Stale]
    }

    /// Remembers a folder, or a file another app handed over. Adding one already
    /// remembered is a no-op.
    ///
    /// Which of the two it is is recorded here, while the URL still exists to be asked. A
    /// bookmark that no longer resolves cannot say what it once pointed at, and the answer
    /// decides whether the reader is told a library of theirs has gone.
    public func add(_ url: URL) throws {
        var stored = raw()
        let bookmark = try url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let name = url.lastPathComponent
        guard !stored.contains(where: { $0.name == name && $0.data == bookmark }) else { return }
        let isFile = !Self.isDirectory(url)
        // 10.3: a key of its own, not the name. Two folders picked under the same name
        // used to become one source and one bookmark, because both the registry's locator
        // and this store's own identity were the name.
        stored.append(Entry(name: name, data: bookmark, isFile: isFile, key: UUID().uuidString))
        if isFile { stored = Self.trimmingOldestFiles(stored) }
        write(stored)
    }

    /// A folder's own identity: stable across launches, and unique even when another
    /// folder shares its name. `nil` only when the url was never remembered at all.
    ///
    /// Cached after the first resolution. A folder bookmarked before this existed has no
    /// key on disk yet; one is minted and written back the first time anything asks, the
    /// same way `restore()` backfills one for every entry it resolves.
    public func key(for url: URL) -> String? {
        if let cached = cache.keys[url] { return cached }
        guard let bookmark = try? url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return nil }
        var stored = raw()
        guard let index = stored.firstIndex(where: { $0.data == bookmark }) else { return nil }
        let resolved = stored[index].key ?? UUID().uuidString
        if stored[index].key == nil {
            stored[index].key = resolved
            write(stored)
        }
        cache.keys[url] = resolved
        return resolved
    }

    /// How many single files are kept, oldest dropped first.
    ///
    /// A folder is a library the reader picked, added deliberately and removed the same way,
    /// so folders are not counted. A file arrives every time they open a comic from another
    /// app, and nothing in the app asks them whether they meant to keep it — so the list has
    /// to end somewhere, or a year of previewing other people's comics is a shelf full of
    /// them and an archive opened for each one at every launch.
    ///
    /// Twenty: enough to hold the books someone is actually reading out of Files or a chat,
    /// small enough that the oldest falling off is a forgetting the reader would agree with.
    public static let rememberedFileLimit = 20

    private static func trimmingOldestFiles(_ entries: [Entry]) -> [Entry] {
        let files = entries.filter(\.wasFile)
        guard files.count > rememberedFileLimit else { return entries }
        let dropped = Set(files.prefix(files.count - rememberedFileLimit).map(\.data))
        return entries.filter { !$0.wasFile || !dropped.contains($0.data) }
    }

    /// Every place still reachable, plus the folders that are not.
    ///
    /// Resolving *starts* the security-scoped access and deliberately does not stop
    /// it: the library reads pages out of these folders for as long as it is open,
    /// and balancing the call here would revoke access before the first cover loads.
    ///
    /// A file that has gone is dropped rather than reported. `local-library` names an
    /// unavailable *folder* and offers a single action to re-pick it; a file another app
    /// handed over was never a library the reader configured, so there is no library for
    /// them to pick again and nothing they could do with the notice.
    public func restore() -> Restored {
        var folders: [URL] = []
        var files: [URL] = []
        var stale: [Stale] = []
        var survivors: [Entry] = []
        // Set when a survivor's key was just minted, so a pre-10.3 entry that still
        // resolves gets one written back even though its count has not changed.
        var backfilledAKey = false

        for entry in raw() {
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: entry.data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                if !entry.wasFile { stale.append(Stale(name: entry.name)) }
                continue
            }
            guard url.startAccessingSecurityScopedResource() else {
                // Resolvable but not accessible: the grant is gone even though the
                // path is still valid, which is what a revoked permission looks
                // like. Reported rather than silently dropped, because
                // `local-library` requires a single action to re-pick it.
                if !entry.wasFile { stale.append(Stale(name: entry.name)) }
                continue
            }
            // Asked of the filesystem rather than read back from the entry, so a bookmark
            // written before this store told the two apart still lands in the right list —
            // and so does one whose folder has since become a file, or the reverse.
            if Self.isDirectory(url) { folders.append(url) } else { files.append(url) }
            if entry.key == nil { backfilledAKey = true }
            let key = entry.key ?? UUID().uuidString
            if !entry.wasFile { cache.keys[url] = key }
            // A stale bookmark still resolved, so it is refreshed rather than
            // reported: the folder moved and the system found it anyway.
            if isStale, let refreshed = try? url.bookmarkData(options: .minimalBookmark) {
                survivors.append(
                    Entry(name: url.lastPathComponent, data: refreshed, isFile: entry.wasFile, key: key)
                )
            } else {
                var survivor = entry
                survivor.key = key
                survivors.append(survivor)
            }
        }

        // Unresolvable entries are dropped, so a folder that has gone for good does
        // not report itself every launch for ever. A newly-minted key is written back
        // the same way, even on a launch where nothing else changed.
        if survivors.count != raw().count || backfilledAKey { write(survivors) }
        return Restored(folders: folders, files: files, stale: stale)
    }

    /// Whether a URL is a directory, according to the filesystem rather than to its spelling.
    ///
    /// `hasDirectoryPath` reads the trailing slash, and a URL resolved from a bookmark or
    /// handed over by another app does not reliably carry one.
    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }

    /// Forgets a folder. Reading progress for what was inside it is untouched —
    /// ADR-0006 keys progress on the publication, not on the folder it came from.
    public func remove(named name: String) {
        write(raw().filter { $0.name != name })
    }

    /// Forgets one folder by its own key, leaving every other folder of the same name.
    /// `remove(named:)` drops all of them, which is exactly the defect 10.3 fixes.
    public func remove(key: String) {
        write(raw().filter { $0.key != key })
    }

    public func removeAll() {
        defaults.removeObject(forKey: key)
    }

    // MARK: - Storage

    private struct Entry: Codable {
        let name: String
        let data: Data
        /// Whether this was a single file when it was remembered.
        ///
        /// Optional so an entry written before the distinction existed still decodes. It is
        /// only consulted for an entry whose bookmark no longer resolves, and there the
        /// missing value reads as "a folder", which is what every entry written by those
        /// builds was meant to be.
        let isFile: Bool?
        /// This folder's own identity, independent of its name. Optional for the same
        /// reason `isFile` is — an entry written before 10.3 has none yet — and backfilled
        /// the first time `restore()` or `key(for:)` resolves it.
        var key: String?

        var wasFile: Bool { isFile ?? false }
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
