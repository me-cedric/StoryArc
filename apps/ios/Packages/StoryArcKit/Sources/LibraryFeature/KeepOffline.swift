internal import Foundation

internal import Persistence
internal import StoryArcCore

/// Downloading, for a publication that is already a file.
///
/// `collections-and-reading-lists` asks for a selection to be downloaded and for the app to
/// state "the item count and total size before starting". Everything in the library came
/// off a folder the reader picked, so there is nothing to fetch — but a picked folder is
/// exactly the thing that goes away. ``LibraryModel/unavailableFolders`` exists because it
/// does: a card is removed, a share is unmounted, a bookmark goes stale, and the shelf
/// empties. `offline-downloads` promises that what has been downloaded stays readable, and
/// this is how a local publication earns that promise: its bytes are copied into the app's
/// own download store, recorded like any other download, and are then visible, countable
/// and removable in Settings › Downloads and storage.
///
/// The same act as the app layer's keep-for-offline, which does this for one publication on
/// an unreachable share. This is that path applied to a set.
extension LibraryModel {
    /// Which publications already have a copy of their own.
    ///
    /// Read when the reader asks rather than held: it is wanted twice in a confirmation and
    /// never during a redraw, and a cached copy would disagree with Settings the moment a
    /// download was removed there.
    var keptOffline: Set<String> { Set(DownloadStore().library().downloads.map(\.id)) }

    /// What a selection weighs on disk, for the confirmation that has to state a size.
    ///
    /// Nothing for a publication whose file cannot be measured, rather than a guess: the
    /// requirement is that a size is *shown*, and an invented one is worse than a short one.
    func bytesOnDisk(of ids: Set<String>) -> Int64 {
        ids.reduce(into: Int64(0)) { total, id in
            guard let publication = publications.first(where: { $0.id == id }),
                  let url = location(of: publication),
                  let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            else { return }
            total += Int64(size)
        }
    }

    /// Copies a whole selection into the download store, and reports what it copied.
    @discardableResult
    func keepOffline(_ selection: Set<String>) async -> Set<String> {
        let wanted = BulkSelection.downloading(selection, onDevice: keptOffline)
        let store = DownloadStore()
        try? store.prepare()

        var kept: Set<String> = []
        for id in wanted {
            guard let publication = publications.first(where: { $0.id == id }),
                  // A folder of images has no single file to copy, and saying so by
                  // skipping it beats copying a directory the reader never asked about.
                  publication.format != .imageFolder,
                  let url = location(of: publication),
                  let bytes = await copy(publication, at: url, into: store)
            else { continue }
            record(publication, from: url, bytes: bytes, in: store)
            kept.insert(id)
        }
        return kept
    }

    /// Forgets copies this made, deleting the files with them.
    func forgetKept(_ ids: Set<String>) {
        let store = DownloadStore()
        var library = store.library()
        for id in ids { library = store.removing(id, from: library) }
    }

    /// Puts one publication's bytes beside the other downloads, off the main actor.
    private func copy(
        _ publication: Publication,
        at url: URL,
        into store: DownloadStore
    ) async -> Int64? {
        // A folder of images has no media type and is not one file, so there is nothing
        // here to copy. It is also already on the device, which is what this exists for.
        guard let mediaType = publication.format.mediaType else { return nil }
        // The same three inputs the record below carries, so the copy is written where a
        // later removal will look for it. This used to name the file by identity alone,
        // deliberately, to work around Settings deleting a path the queue never wrote —
        // the store decides now, so the workaround is gone with the disagreement.
        let destination = store.location(
            for: publication.id,
            mediaType: mediaType,
            title: publication.displayTitle
        )
        return await Task.detached(priority: .utility) { () -> Int64? in
            let manager = FileManager.default
            try? manager.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            // Replaced rather than refused: a copy left behind by a removal that only got
            // half way is not a reason to tell the reader their comic cannot be kept.
            try? manager.removeItem(at: destination)
            guard (try? manager.copyItem(at: url, to: destination)) != nil,
                  let size = try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize
            else { return nil }
            return Int64(size)
        }.value
    }

    /// Writes the record that makes the copy a download rather than a stray file.
    private func record(
        _ publication: Publication,
        from url: URL,
        bytes: Int64,
        in store: DownloadStore
    ) {
        // The copy would not exist without one; `copy` refuses before reaching here.
        guard let mediaType = publication.format.mediaType else { return }
        store.save(
            store.library().queueing(
                Download(
                    id: publication.id,
                    sourceID: publication.sourceID,
                    title: publication.displayTitle,
                    // Where it came from, which for this one is the reader's own folder.
                    remote: url,
                    mediaType: mediaType,
                    state: .finished,
                    expectedBytes: bytes,
                    downloadedBytes: bytes,
                    completedAt: Date()
                )
            )
        )
    }
}
