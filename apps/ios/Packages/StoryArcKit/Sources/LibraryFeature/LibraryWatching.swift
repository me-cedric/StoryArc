public import Foundation

internal import Formats
internal import StoryArcCore

/// Keeping the library in step with folders that change under it.
///
/// `local-library`'s watched changes: a file added to a watched folder "appears in the
/// library within 10 seconds without a manual refresh", and a change made while the app was
/// away is reconciled "by comparing file modification times and sizes rather than re-reading
/// every archive".
///
/// Two halves, and they meet here. ``FolderWatcher`` is told when something happened;
/// ``FolderSnapshot`` decides what it was. Only the second is mirrored on Android — the
/// first cannot be, because the platforms are told about a change in entirely different
/// ways.
extension LibraryModel {
    /// Watches every folder the reader added.
    ///
    /// Called whenever the set of folders changes, which is the only thing that invalidates
    /// what is being watched.
    func startWatching() {
        guard !folders.isEmpty else {
            watcher.stop()
            return
        }
        watcher.watch(folders) { [weak self] in
            Task { await self?.reconcileWatchedFolders() }
        }
    }

    /// Stops watching. The library stays; only the descriptors go.
    public func stopWatching() {
        watcher.stop()
    }

    /// Brings every watched folder up to date.
    public func reconcileWatchedFolders() async {
        for folder in folders { await reconcile(folder) }
    }

    /// Notices what changed in one folder, and re-reads only that.
    ///
    /// Nothing happens at all when the folder is unchanged, which is the common case: the
    /// listing is compared, it matches, and not one archive is opened.
    func reconcile(_ folder: URL) async {
        let walked = LibraryScanner.entries(in: folder)
        let snapshot = snapshots[folder.path] ?? FolderSnapshot()
        // Nil means the walk found nothing where something used to be — an unreadable
        // folder far more often than a reader who deleted every book. Nothing is removed
        // and the snapshot is left alone; see `FolderSnapshot.change(to:)`.
        guard let change = snapshot.change(to: walked), !change.isEmpty else { return }

        let sourceID = source(of: folder)
        for path in change.removed { forget(path) }
        // A changed file is re-read from scratch rather than patched: its series, its page
        // count and its cover can all have moved, and there is no cheaper honest answer.
        for entry in change.changed { forget(entry.path) }

        for entry in change.toIndex {
            let url = URL(fileURLWithPath: entry.path)
            guard let publication = try? await PublicationIndexer.index(
                fileAt: url,
                // The folder a publication sits in is its series, exactly as during a scan.
                // The library's own folder is not one, so a file at the top level gets none.
                seriesHint: url.deletingLastPathComponent() == folder
                    ? nil
                    : url.deletingLastPathComponent().lastPathComponent
            ) else { continue }
            adopt(publication, from: sourceID)
            locations[publication.id] = url
        }

        snapshots[folder.path] = snapshot.updated(to: walked)
        // The watched set is re-read too: a new series folder is a new directory, and a
        // directory nobody opened a descriptor on reports nothing.
        startWatching()
        rebuild()
        await refreshProgress()
    }

    /// Drops the row for a file that has gone or has been replaced.
    ///
    /// By path rather than by identity, because the path is the only thing a directory
    /// listing knows — and it is what ``locations`` is keyed on for exactly this.
    private func forget(_ path: String) {
        let gone = locations.filter { $0.value.path == path }.map(\.key)
        guard !gone.isEmpty else { return }
        publications.removeAll { gone.contains($0.id) }
        for id in gone { locations.removeValue(forKey: id) }
    }
}
