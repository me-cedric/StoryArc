public import Foundation

/// What a folder held the last time it was looked at.
///
/// `local-library` requires the app to "detect changes to a folder library without a full
/// rescan", and to reconcile "by comparing file modification times and sizes rather than
/// re-reading every archive". Those two sentences are this type. A walk that reads only
/// directory entries is cheap; comparing one against the last one says exactly which files
/// have to be opened, and opening a file is the expensive part.
///
/// Pure, and identical on Android. It is the arithmetic of noticing a change, not the
/// mechanism of being told about one — the mechanisms have nothing in common between the
/// two platforms and this has to.
public struct FolderSnapshot: Sendable, Equatable {
    /// One publication, as a directory listing describes it.
    ///
    /// The modification date and the size together, because either alone misses a real
    /// case: a file replaced with one of the same length keeps its size, and a file copied
    /// back from a backup keeps its date.
    public struct Entry: Sendable, Equatable, Hashable {
        public let path: String
        public let modified: Date
        public let size: Int64

        public init(path: String, modified: Date, size: Int64) {
            self.path = path
            self.modified = modified
            self.size = size
        }
    }

    /// What was there, keyed by path.
    public private(set) var entries: [String: Entry]

    public init(_ entries: [Entry] = []) {
        self.entries = Dictionary(entries.map { ($0.path, $0) }) { first, _ in first }
    }

    /// What has to be done to catch up with a fresh walk.
    public struct Change: Sendable, Equatable {
        /// Files that were not there before.
        public var added: [Entry] = []
        /// Files whose modification time or size has moved.
        public var changed: [Entry] = []
        /// Files that have gone. Their rows go with them.
        public var removed: [String] = []

        public var isEmpty: Bool { added.isEmpty && changed.isEmpty && removed.isEmpty }

        /// The only files that have to be opened, which is the whole point of comparing.
        public var toIndex: [Entry] { added + changed }
    }

    /// What changed since this snapshot, or `nil` when the walk cannot be believed.
    ///
    /// `nil` for a walk that found nothing at all where something used to be. A folder whose
    /// permission has gone stale, or a file provider that has not finished mounting, walks
    /// as empty — and reading that as "the reader deleted every book" empties their library.
    /// Refusing is the safe answer: a reader who really did empty the folder still has a
    /// full rescan, and a reader whose provider was slow keeps their library.
    public func change(to walked: [Entry]) -> Change? {
        guard !walked.isEmpty || entries.isEmpty else { return nil }

        var change = Change()
        var seen: Set<String> = []
        for entry in walked {
            seen.insert(entry.path)
            guard let known = entries[entry.path] else {
                change.added.append(entry)
                continue
            }
            if known != entry { change.changed.append(entry) }
        }
        // Sorted, so a reconcile does the same thing twice given the same folder — a
        // dictionary's order is not one, and a test that asserted on it would flake.
        change.removed = entries.keys.filter { !seen.contains($0) }.sorted()
        return change
    }

    /// The snapshot a walk leaves behind.
    ///
    /// The second half of the same guard as ``change(to:)``: a walk that found nothing where
    /// something used to be leaves the snapshot alone. Overwriting it would throw away the
    /// only record of what the folder held, so the pass after the provider came back would
    /// see every file as new and re-read every archive.
    public func updated(to walked: [Entry]) -> FolderSnapshot {
        walked.isEmpty && !entries.isEmpty ? self : FolderSnapshot(walked)
    }
}
