import Foundation

import Formats
import Persistence
import StoryArcCore

/// Copies a publication off a share and onto the device.
///
/// `network-share`: when reconnection has failed for a minute "the app offers to download
/// the current publication for offline reading". This is that offer carried out — the bytes
/// are fetched once and the reader reopens from the copy, so the rest of the session no
/// longer depends on the network.
///
/// Returns where the copy landed, or `nil` when the share is still unreachable, which is
/// the likeliest outcome and not a surprise: the offer exists because the network is down.
///
/// A file of its own, beside Android's `KeepForOffline.kt`, because `StoryArcApp` is at its
/// line cap and this is a whole job rather than a step of one.
///
/// **Named by the download store, not by the server.** The destination used to be
/// `directory.appending(path: remote.lastPathComponent)` — `lastPathComponent` decodes
/// percent escapes, so a share entry named `..%2F..%2FLibrary%2Fx.cbz` resolved outside the
/// download directory entirely, the same class of defect `SmbEntry.cacheLocation` closed for
/// the share browser. `DownloadStore.location(for:mediaType:title:)` is what already answers
/// this for every other writer of a download: keyed on the publication's own identity, never
/// on anything the server sent.
///
/// **Recorded, not merely written.** The bytes used to land with no ``Download`` entry at
/// all, so the copy was invisible to *On device* and to the storage total — Android has
/// recorded its own copy since the file was written; this brings iOS to the same place. The
/// recording itself happens back in ``StoryArcAppActions/keepForOffline(_:)``, on the actor
/// ``DownloadStore`` actually belongs to: the store holds a `UserDefaults`, which is not
/// `Sendable`, so it never crosses in here — only the plain `URL` of its directory does, and
/// ``KeptOfflineCopy`` carries back everything the recording needs.
///
/// - Parameter directory: where the copy goes, which is the download store's own. Passed as
///   a path rather than as the store, so nothing main-actor-isolated crosses into here.
func keptForOffline(_ selection: ReadingSelection, into directory: URL) async -> KeptOfflineCopy? {
    let publication = selection.publication
    guard let mediaType = publication.format.mediaType,
          let source = try? await ComicArchiveOpener.source(for: selection.url)
    else { return nil }

    let file = DownloadStore.location(
        for: publication.id, mediaType: mediaType, title: publication.displayTitle, in: directory
    )
    do {
        try await ChunkedCopy.copy(source, to: file)
    } catch {
        return nil
    }
    DownloadStore.protect(file)
    return KeptOfflineCopy(file: file, mediaType: mediaType, bytes: source.length)
}

/// What a finished copy needs recorded, carried back across the isolation boundary
/// ``keptForOffline(_:into:)`` runs behind.
struct KeptOfflineCopy: Sendable {
    let file: URL
    let mediaType: String
    let bytes: Int64
}
