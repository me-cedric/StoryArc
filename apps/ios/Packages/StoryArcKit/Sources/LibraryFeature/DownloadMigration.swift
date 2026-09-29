internal import Foundation

internal import Catalogue
internal import StoryArcCore

/// Fixes an OPDS download recorded before source-keyed ids existed.
///
/// `offline-downloads` dl-core 1.2: a download queued before this fix carries the bare
/// catalogue entry id and no source, so a second catalogue that numbers its entries the
/// same way shares its record and its file. Nothing can recover a source for a stray
/// record in general — the source was never written down — but the queue for one
/// catalogue knows its own origin, and a stray record whose remote address belongs to that
/// origin can only be that catalogue's. Migrating there, rather than in one pass over every
/// source, needs no registry and touches only the strays a queue is actually about to
/// reuse — which is also every stray this app will ever open again.
enum DownloadMigration {
    /// Re-keys every stray this origin owns, and says which directories moved so the store
    /// can rename them on disk.
    ///
    /// A record already carrying a source is left alone — it was written by this fix or by
    /// Kavita or a local keep, all of which already attribute correctly — so a repeat call
    /// on every launch does nothing once every stray this origin owns has been found.
    static func migrating(
        _ library: DownloadLibrary,
        sourceID: UUID,
        origin: OpdsOrigin
    ) -> (library: DownloadLibrary, renamed: [(from: String, to: String)]) {
        var renamed: [(from: String, to: String)] = []
        let migrated = library.downloads.map { download -> Download in
            guard download.sourceID == nil, OpdsOrigin(url: download.remote) == origin else {
                return download
            }
            let newID = "opds:\(sourceID.uuidString):\(download.id)"
            renamed.append((from: download.id, to: newID))
            return Download(
                id: newID,
                sourceID: sourceID,
                title: download.title,
                remote: download.remote,
                mediaType: download.mediaType,
                state: download.state,
                expectedBytes: download.expectedBytes,
                downloadedBytes: download.downloadedBytes,
                completedAt: download.completedAt,
                verificationFailures: download.verificationFailures
            )
        }
        guard !renamed.isEmpty else { return (library, []) }
        return (DownloadLibrary(downloads: migrated), renamed)
    }
}
