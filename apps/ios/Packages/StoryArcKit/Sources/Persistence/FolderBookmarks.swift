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
        stored.append(Entry(name: name, data: bookmark, isFile: isFile))
        if isFile { stored = Self.trimmingOldestFiles(stored) }
        write(stored)
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
            // A stale bookmark still resolved, so it is refreshed rather than
            // reported: the folder moved and the system found it anyway.
            if isStale, let refreshed = try? url.bookmarkData(options: .minimalBookmark) {
                survivors.append(
                    Entry(name: url.lastPathComponent, data: refreshed, isFile: entry.wasFile)
                )
            } else {
                survivors.append(entry)
            }
        }

        // Unresolvable entries are dropped, so a folder that has gone for good does
        // not report itself every launch for ever.
        if survivors.count != raw().count { write(survivors) }
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
