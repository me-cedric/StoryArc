import Foundation

/// One folder a reader chose, and whether the app can read it right now.
///
/// `desktop-experience`, *Choosing folders and keeping access*: a folder whose access was
/// withdrawn shows in grey as needing access and offers one action to choose it again; one
/// on an unmounted volume shows as offline and returns by itself when the volume does.
/// Task 2.19.
struct FolderSource: Identifiable, Equatable, Sendable {
    enum State: Equatable, Sendable {
        case available
        /// The bookmark no longer resolves, or the system refused the grant.
        case needsAccess
        /// The bookmark resolves and the path is not there: a volume that is not connected.
        case offline
    }

    let key: String
    let name: String
    let url: URL?
    var state: State

    var id: String { key }
    var isGrey: Bool { state != .available }
}

/// A folder the bookmark store resolved: its key, the name it shows and where it is now.
struct RememberedFolder: Equatable, Sendable {
    let key: String
    let name: String
    let url: URL
}

/// The states of every remembered folder, from what the bookmark store restored.
enum FolderSourceStates {
    static func resolve(
        folders: [RememberedFolder],
        stale: [String],
        isReachable: (URL) -> Bool
    ) -> [FolderSource] {
        let reachable = folders.map { folder in
            FolderSource(
                key: folder.key, name: folder.name, url: folder.url,
                state: isReachable(folder.url) ? .available : .offline
            )
        }
        let withdrawn = stale.map { name in
            FolderSource(key: "stale:\(name)", name: name, url: nil, state: .needsAccess)
        }
        return reachable + withdrawn
    }

    /// The sources after a volume came or went: offline ones re-checked, nothing else moved.
    static func revisited(_ sources: [FolderSource], isReachable: (URL) -> Bool) -> [FolderSource] {
        sources.map { source in
            guard source.state != .needsAccess, let url = source.url else { return source }
            var next = source
            next.state = isReachable(url) ? .available : .offline
            return next
        }
    }
}
