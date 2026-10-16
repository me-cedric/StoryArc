import Foundation

/// A folder the Mac app was granted access to, remembered across launches.
///
/// `FolderBookmarks` in `Persistence` mints `.minimalBookmark` bookmarks, which is right on
/// iOS and wrong under App Sandbox: a Mac needs `.withSecurityScope` on create and on
/// resolve, or the second launch cannot read the folder the first one was given
/// (`design.md` Decision 2 and Decision 8). The package lives under `apps/ios`, so this
/// wrapper carries the fix until task 1.30 moves it into `Persistence`. Kept to the three
/// things the task names — the option on both calls, a refresh of a stale bookmark, and a
/// `start` that is balanced by exactly one `stop` — and nothing the iOS store already does.
///
/// Its own `UserDefaults` key, so it never reads an iOS-shaped entry as a Mac one.
struct MacFolderBookmarks {
    static let defaultKey = "app.storyarc.mac.libraryFolders"

    private let defaults: UserDefaults
    private let key: String
    private let system: any SecurityScopedBookmarking

    init(
        defaults: UserDefaults = .standard,
        key: String = MacFolderBookmarks.defaultKey,
        bookmarking: any SecurityScopedBookmarking = SystemBookmarking()
    ) {
        self.defaults = defaults
        self.key = key
        self.system = bookmarking
    }

    /// A folder that could not be re-opened, named so the message can say which.
    struct Stale: Equatable, Sendable {
        let name: String
    }

    struct Restored {
        /// Every folder still reachable. Each one is being accessed until its `end()`.
        let folders: [FolderAccess]
        let stale: [Stale]
    }

    /// Remembers a folder. Adding one already remembered is a no-op.
    ///
    /// Already remembered means the same path: two mints of one URL are not the same
    /// bytes, so the bookmark data is no identity.
    func add(_ url: URL) throws {
        var stored = raw()
        let path = Self.path(of: url)
        guard !stored.contains(where: { $0.path == path }) else { return }
        let bookmark = try system.bookmarkData(for: url, options: .withSecurityScope)
        stored.append(Entry(name: url.lastPathComponent, path: path, data: bookmark, key: UUID().uuidString))
        write(stored)
    }

    private static func path(of url: URL) -> String {
        url.standardizedFileURL.path(percentEncoded: false)
    }

    /// Every folder still reachable, with access started, plus the ones that are not.
    ///
    /// A bookmark the system calls stale still resolved, so it is minted again rather than
    /// reported: the folder moved and the system found it anyway. One that does not resolve
    /// is dropped, so a folder gone for good does not report itself at every launch.
    func restore() -> Restored {
        var folders: [FolderAccess] = []
        var stale: [Stale] = []
        var survivors: [Entry] = []
        var refreshedOne = false

        for entry in raw() {
            guard let resolved = try? system.resolve(entry.data, options: .withSecurityScope) else {
                stale.append(Stale(name: entry.name))
                continue
            }
            guard system.startAccessing(resolved.url) else {
                // Resolvable but refused: the grant is gone though the path is valid, which
                // is what a revoked permission looks like. Nothing was started, so nothing
                // is stopped.
                stale.append(Stale(name: entry.name))
                continue
            }
            let url = resolved.url
            folders.append(FolderAccess(url: url, key: entry.key, name: entry.name) { [system] in
                system.stopAccessing(url)
            })
            if resolved.isStale,
               let fresh = try? system.bookmarkData(for: url, options: .withSecurityScope) {
                refreshedOne = true
                survivors.append(
                    Entry(name: url.lastPathComponent, path: Self.path(of: url), data: fresh, key: entry.key)
                )
            } else {
                survivors.append(entry)
            }
        }

        if survivors.count != raw().count || refreshedOne { write(survivors) }
        return Restored(folders: folders, stale: stale)
    }

    /// Forgets one folder by its own key. Reading progress is untouched (ADR-0006).
    func remove(key: String) {
        write(raw().filter { $0.key != key })
    }

    func removeAll() {
        defaults.removeObject(forKey: key)
    }

    // MARK: - Storage

    private struct Entry: Codable {
        let name: String
        /// Where the folder was when it was remembered, the identity `add` dedupes on.
        let path: String
        let data: Data
        let key: String
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

/// Access to one restored folder, for as long as this value lives.
///
/// The balance the task asks for. `FolderBookmarks` on iOS starts access and never stops
/// it, on purpose. A Mac keeps a library window open for days and re-resolves folders on
/// every rescan, and each unbalanced `start` is a kernel resource that is never given back.
/// `end()` is idempotent; a handle that is dropped without it stops on its way out.
final class FolderAccess {
    let url: URL
    /// The folder's own identity, stable across launches and unique across folders that
    /// share a name.
    let key: String
    let name: String

    private var isActive = true
    private let stop: () -> Void

    init(url: URL, key: String, name: String, stop: @escaping () -> Void) {
        self.url = url
        self.key = key
        self.name = name
        self.stop = stop
    }

    func end() {
        guard isActive else { return }
        isActive = false
        stop()
    }

    deinit { end() }
}

/// What resolving a bookmark gave back.
struct ResolvedBookmark {
    let url: URL
    let isStale: Bool
}

/// The four system calls the store makes, behind a seam so a test can see the options.
protocol SecurityScopedBookmarking {
    func bookmarkData(for url: URL, options: URL.BookmarkCreationOptions) throws -> Data
    func resolve(_ bookmark: Data, options: URL.BookmarkResolutionOptions) throws -> ResolvedBookmark
    func startAccessing(_ url: URL) -> Bool
    func stopAccessing(_ url: URL)
}

/// The real calls.
struct SystemBookmarking: SecurityScopedBookmarking {
    func bookmarkData(for url: URL, options: URL.BookmarkCreationOptions) throws -> Data {
        try url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    func resolve(_ bookmark: Data, options: URL.BookmarkResolutionOptions) throws -> ResolvedBookmark {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: options,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return ResolvedBookmark(url: url, isStale: isStale)
    }

    func startAccessing(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}
