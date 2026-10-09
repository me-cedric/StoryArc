public import Foundation

/// Where the reader chose to keep the sync document.
public enum SyncPlaceChoice: Sendable, Equatable {
    /// A share the reader already added, by its source id.
    case share(sourceID: UUID)
    /// A folder picked through the system picker, by its last known name. The folder itself is
    /// a security-scoped bookmark.
    case folder(name: String)
}

/// Why a picked folder cannot be the sync place.
public enum SyncFolderRefusal: Error, Equatable {
    /// The folder is a library: the app's own Documents folder or one inside it, a folder the
    /// library reads, or the File Provider storage root that holds the app's folder. The sync
    /// document would land among the books. Android refuses a library folder the same way.
    case isLibrary
}

/// The sync place, on this device only.
///
/// `library-sync` task 2.1. Not in `AppSettings`, because the settings travel in the sync
/// document and each device reaches the place by its own path. No choice means sync is off:
/// nothing is written, read or looked for. Android's `SyncPlaceStore` keeps the same value.
///
/// A picked folder is kept the way `local-library` keeps one (task 2.3): a security-scoped
/// bookmark in ``FolderBookmarks``, under a key of its own so the library never reads it as one
/// of its folders.
///
/// `@unchecked Sendable`: it holds a `UserDefaults`, which is documented as safe to use from
/// any thread but is not marked so.
public struct SyncPlaceStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "app.storyarc.syncPlace"
    private let resolved = Resolved()
    private let documents: URL

    /// The folder, resolved once per launch. Each resolution starts the security scope, and the
    /// scope stays open while the app runs, as the library's folders do.
    private final class Resolved: @unchecked Sendable {
        let lock = NSLock()
        var folder: URL?
    }

    /// - Parameter documents: the app's own Documents folder, which is the library folder.
    public init(defaults: UserDefaults = .standard, documents: URL = .documentsDirectory) {
        self.defaults = defaults
        self.documents = documents
    }

    private var bookmarks: FolderBookmarks { FolderBookmarks(defaults: defaults, key: "app.storyarc.syncFolder") }

    /// The chosen place, or nil while sync is off.
    public func choice() -> SyncPlaceChoice? {
        guard let stored = defaults.string(forKey: key) else { return nil }
        if stored.hasPrefix(Self.share) {
            return UUID(uuidString: String(stored.dropFirst(Self.share.count))).map { .share(sourceID: $0) }
        }
        if stored.hasPrefix(Self.folder) { return .folder(name: String(stored.dropFirst(Self.folder.count))) }
        return nil
    }

    /// Chooses a share. A folder chosen before is forgotten.
    public func chooseShare(_ sourceID: UUID) {
        forgetFolder()
        defaults.set(Self.share + sourceID.uuidString, forKey: key)
    }

    /// Chooses a folder the system picker returned. The caller holds its security scope open
    /// while this runs, because the bookmark is made from it.
    ///
    /// - Throws: ``SyncFolderRefusal/isLibrary`` for a library folder, with nothing changed.
    public func chooseFolder(_ url: URL) throws {
        guard !isLibrary(url) else { throw SyncFolderRefusal.isLibrary }
        forgetFolder()
        try bookmarks.add(url)
        defaults.set(Self.folder + url.lastPathComponent, forKey: key)
    }

    /// Turns sync off.
    public func turnOff() {
        forgetFolder()
        defaults.removeObject(forKey: key)
    }

    /// The chosen folder, re-opened from its bookmark, or nil when it has gone.
    public func folder() -> URL? {
        resolved.lock.withLock {
            if let held = resolved.folder { return held }
            resolved.folder = bookmarks.restore().folders.first
            return resolved.folder
        }
    }

    /// Whether `url` is a library folder. `library-sync` task 5.5.
    func isLibrary(_ url: URL) -> Bool {
        let path = Self.path(of: url)
        let library = Self.path(of: documents)
        return url.lastPathComponent == Self.storageRoot
            || path == library || path.hasPrefix(library + "/")
            || FolderBookmarks(defaults: defaults).key(for: url) != nil
    }

    /// The name of the folder the system picker opens as On My iPhone.
    static let storageRoot = "File Provider Storage"

    private static func path(of url: URL) -> String {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    private func forgetFolder() {
        resolved.lock.withLock {
            resolved.folder?.stopAccessingSecurityScopedResource()
            resolved.folder = nil
        }
        bookmarks.removeAll()
    }

    private static let share = "share:"
    private static let folder = "folder:"
}
