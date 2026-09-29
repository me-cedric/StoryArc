internal import Foundation

internal import Catalogue
internal import Persistence
internal import StoryArcCore

/// Fixes an OPDS download recorded before source-keyed ids existed.
///
/// `offline-downloads` dl-core 1.2: a download queued before this fix carries the bare
/// catalogue entry id and no source, so a second catalogue that numbers its entries the
/// same way shares its record and its file. Nothing can recover a source for a stray
/// record in general — the source was never written down — but each catalogue knows its
/// own origin, and a stray record whose remote address belongs to that origin can only be
/// that catalogue's. The shared queue runs this pass for every catalogue before it reads
/// the store — see ``migratingStrays(in:sources:)``.
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

    /// Re-keys every stray that a registered catalogue owns, before the shared queue reads
    /// the store.
    ///
    /// The one app-level queue (dl-core 1.1) has no origin of its own, so it cannot run the
    /// per-origin pass above for itself. This runs that pass once for each OPDS catalogue.
    /// When two catalogues share an origin, the first one in the registry takes the stray.
    static func migratingStrays(in store: DownloadStore, sources: [Source]) {
        var library = store.library()
        var renamed: [(from: String, to: String)] = []
        for source in sources where source.kind == .opdsCatalog {
            guard let locator = source.locator, let home = URL(string: locator),
                  let origin = OpdsOrigin(url: home)
            else { continue }
            let step = migrating(library, sourceID: source.id, origin: origin)
            library = step.library
            renamed += step.renamed
        }
        guard !renamed.isEmpty else { return }
        for pair in renamed { store.renaming(pair.from, to: pair.to) }
        store.save(library)
    }
}
