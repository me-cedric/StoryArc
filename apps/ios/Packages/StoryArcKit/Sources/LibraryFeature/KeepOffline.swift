internal import Foundation

internal import Catalogue
internal import Kavita
internal import Persistence
internal import StoryArcCore

/// How `OpdsContributor` names an entry's remote identifier, so a row built from one can be
/// told apart from a Kavita chapter's `"chapter:"`.
private let opdsRemoteIDPrefix = "opds:"

/// Finding, in a freshly read feed, the one entry a catalogue-only row names.
///
/// Its own type so the matching can be driven by a feed of the test's own choosing — the
/// rule is "which entry and which acquisition", and that question has nothing to do with
/// how the feed arrived. Android's `RemoteMemberResolution` is the same rule.
enum RemoteMemberResolution {
    /// `remoteID` as `OpdsContributor` wrote it onto the row's identity, and `feed` as read
    /// again from that row's own source. `nil` for anything that is not an OPDS remote id,
    /// or whose entry the feed no longer lists.
    static func opdsEntry(matching remoteID: String, in feed: OpdsFeed) -> (OpdsEntry, OpdsAcquisition)? {
        guard remoteID.hasPrefix(opdsRemoteIDPrefix) else { return nil }
        let entryID = String(remoteID.dropFirst(opdsRemoteIDPrefix.count))
        guard let entry = feed.publications.first(where: { $0.id == entryID }),
              let acquisition = CatalogueAcquisition.best(of: entry)
        else { return nil }
        return (entry, acquisition)
    }

    /// The id the queue keys an OPDS entry's download under.
    ///
    /// One spelling of that key, because two screens reach it from different halves: a
    /// catalogue page has the entry and its own source — ``DownloadQueue/downloadID(for:sourceID:)``
    /// — and the publication page has only a library row. dl-core 1.2 made the key
    /// source-scoped, and a second copy of the format is a second place for it to drift.
    static func downloadID(entry entryID: String, sourceID: UUID) -> Download.ID {
        "\(opdsRemoteIDPrefix)\(sourceID.uuidString):\(entryID)"
    }

    /// The id the queue keys this library row's own transfer under.
    ///
    /// `offline-downloads`' *The iOS publication page never finds, starts or shows an OPDS
    /// download*. The page asked the download store for the row's own id and therefore found
    /// nothing for every OPDS publication: the row is keyed `srv:<source>:opds:<entry>` — see
    /// ``StoryArcCore/PublicationIdentity/stableID`` — while dl-core 1.2 keys the download
    /// `opds:<source>:<entry>`. With no record the page had no address to stream from, no
    /// state to draw and no progress to move.
    ///
    /// Everything that is not an OPDS row — a local copy, a Kavita keep — is recorded under
    /// the row's own id, which is what the fallback keeps true.
    static func downloadID(of publication: Publication) -> Download.ID {
        guard let server = publication.identity.serverIdentifier,
              server.remoteID.hasPrefix(opdsRemoteIDPrefix)
        else { return publication.id }
        return downloadID(
            entry: String(server.remoteID.dropFirst(opdsRemoteIDPrefix.count)),
            sourceID: server.sourceID
        )
    }

    /// This publication's transfer, under whichever of the two keys names it.
    static func record(of publication: Publication, in library: DownloadLibrary) -> Download? {
        library[downloadID(of: publication)] ?? library[publication.id]
    }

    /// Queues a resolved member, and returns the id its undo takes back.
    ///
    /// The queue's id, not the row's: the row is `srv:<source>:opds:<entry>` and the queue
    /// keys the download `opds:<source>:<entry>`, so an undo by the row's id took nothing
    /// back. `nil` when the queue already held this download — the reader queued it before
    /// the group did, and the group's undo is not theirs to cancel.
    @MainActor
    static func enqueue(
        _ entry: OpdsEntry,
        using acquisition: OpdsAcquisition,
        sourceID: UUID,
        in queue: DownloadQueue
    ) -> Download.ID? {
        let id = queue.downloadID(for: entry.id, sourceID: sourceID)
        guard queue.library[id] == nil else { return nil }
        queue.enqueue(entry, using: acquisition, sourceID: sourceID)
        return id
    }
}

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

    /// What a selection weighs, for the confirmation that has to state a size.
    ///
    /// The file where there is one, and the size the *server* stated where there is not —
    /// `offline-downloads` 6.4. A catalogue-only member has no file to measure, so a group of
    /// ten of them was confirmed as weighing nothing and then fetched hundreds of megabytes.
    ///
    /// Still nothing for a publication neither the filesystem nor the catalogue can measure,
    /// rather than a guess: the requirement is that a size is *shown*, and an invented one is
    /// worse than a short one.
    func bytesOnDisk(of ids: Set<String>) -> Int64 {
        ids.reduce(into: Int64(0)) { total, id in
            guard let publication = publications.first(where: { $0.id == id }) else { return }
            let measured = location(of: publication)
                .flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
                .map(Int64.init) ?? 0
            total += measured > 0 ? measured : (publication.fileSize ?? 0)
        }
    }

    /// Copies a whole selection into the download store, and reports what it copied.
    ///
    /// The record goes through the shared queue rather than a plain `store.save` —
    /// `offline-downloads` 1.1: written straight to the store, this copy used to be undone
    /// the next time any catalogue's own queue saved, because that queue's in-memory copy
    /// knew nothing of the write.
    @discardableResult
    func keepOffline(_ selection: Set<String>, queue: DownloadQueue = .shared()) async -> Set<String> {
        let wanted = BulkSelection.downloading(selection, onDevice: keptOffline)
        let store = DownloadStore()
        try? store.prepare()

        var kept: Set<String> = []
        for id in wanted {
            guard let publication = publications.first(where: { $0.id == id }) else { continue }
            // A folder of images has no single file to copy, and saying so by skipping it
            // beats copying a directory the reader never asked about.
            if let url = location(of: publication), publication.format != .imageFolder {
                guard let bytes = await copy(publication, at: url, into: store) else { continue }
                record(publication, from: url, bytes: bytes, in: queue)
                kept.insert(id)
                continue
            }
            // No local file: a unified-shelf row for a source this device has never
            // fetched from. `collections-and-reading-lists`' bulk download "queues them
            // per offline-downloads" — this is that queueing, for the member kind the
            // copy above cannot reach at all.
            let isKavitaChapter = publication.identity.serverIdentifier?.remoteID.hasPrefix("chapter:") == true
            let queued = isKavitaChapter
                ? await enqueueKavita(publication, queue: queue)
                : await enqueueRemote(publication, queue: queue)
            if let queued { kept.insert(queued) }
        }
        return kept
    }

    /// Where a Kavita chapter's own keep would send it, when the library can say now.
    ///
    /// Synchronous and route-only: the device holds the origin ``KavitaContributor``, an
    /// earlier open, or an earlier keep recorded, and the registry holds a reachable
    /// address for the server that origin names. Nothing here asks the server anything —
    /// that is ``enqueueKavita(_:queue:)``'s to do, once a reader has actually asked.
    /// `origin`'s default reads the real store; a test gives one of its own so proving this
    /// needs neither `UserDefaults.standard` nor a network — the resolver store itself is
    /// `KavitaContributorCatalogOriginTests`' claim, and what this asks is only "given an
    /// origin, is there still a reachable server for it".
    private func kavitaKeepRoute(
        for publication: Publication,
        origin resolvedOrigin: (String) -> KavitaOrigin? = { KavitaProgressStore().resolvedOrigin(of: $0) },
        credentials: CredentialStore? = CredentialStore()
    ) -> (origin: KavitaOrigin, address: KavitaAddress)? {
        guard let server = publication.identity.serverIdentifier,
              server.remoteID.hasPrefix("chapter:"),
              let origin = resolvedOrigin(publication.id),
              let source = registry[server.sourceID],
              let page = KavitaPage(source: source, credentials: credentials)
        else { return nil }
        return (origin, page.address)
    }

    /// Whether a Kavita row the library has only ever listed — never opened, never kept —
    /// can still be downloaded.
    ///
    /// `kavita-server`'s *Keeping a chapter on the device* drew a Download control for
    /// exactly this row that did nothing: see ``enqueueRemote(_:queue:)``'s own doc for the
    /// gap it names. `DetailActions`' header makes the rule this answers: an action a tap
    /// cannot carry out is worse shown than left out.
    func canKeepKavitaChapter(
        _ publication: Publication,
        origin resolvedOrigin: (String) -> KavitaOrigin? = { KavitaProgressStore().resolvedOrigin(of: $0) },
        credentials: CredentialStore? = CredentialStore()
    ) -> Bool {
        kavitaKeepRoute(for: publication, origin: resolvedOrigin, credentials: credentials) != nil
    }

    /// Fetches a chapter the library has only ever listed, and keeps it — `KavitaKeep`'s own
    /// four steps, with the chapter and series it wants rebuilt from what the row and its
    /// origin already carry, because nothing here asks the server for a second copy of
    /// either. Returns the kept publication's own id, which is what the caller inserts into
    /// what this round downloaded.
    private func enqueueKavita(_ publication: Publication, queue: DownloadQueue) async -> Download.ID? {
        guard let (origin, address) = kavitaKeepRoute(for: publication) else { return nil }
        let sourceID = publication.identity.serverIdentifier?.sourceID
        let chapter = KavitaChapter(id: origin.chapterId, number: publication.number ?? "", pages: origin.pages)
        let series = KavitaSeries(
            id: origin.seriesId,
            name: publication.series ?? publication.displayTitle,
            libraryId: origin.libraryId
        )
        let kept = await KavitaKeep.keep(
            KavitaKeep.Subject(chapter: chapter, series: series, metadata: nil, origin: origin, sourceID: sourceID),
            client: KavitaClient(address: address),
            progress: KavitaProgressStore(),
            queue: queue
        )
        return kept.map(\.publication.id)
    }

    /// Queues a catalogue-only member for download, resolving its OPDS acquisition fresh.
    ///
    /// `OpdsContributor` deliberately keeps no acquisition URL on the row — "an OPDS
    /// acquisition link can carry a key in its query, and `sources` forbids a cached
    /// catalogue holding a credential" — so the feed is read again, once, to find the one
    /// entry this row names. A member whose source is unreachable, or whose entry a later
    /// feed no longer lists, is left out rather than failing the rest of the selection.
    ///
    /// Kavita's chapters are not reached here — ``enqueueKavita(_:queue:)`` is the sibling
    /// that is, built the same round the Kavita origin store gained enough to answer this
    /// without a server. Returns the queue's id for what it queued, which is what the undo
    /// takes back.
    private func enqueueRemote(_ publication: Publication, queue: DownloadQueue) async -> Download.ID? {
        guard let server = publication.identity.serverIdentifier,
              let source = registry[server.sourceID],
              let page = CataloguePage(source: source, credentials: CredentialStore()),
              let feed = try? await OpdsClient(origin: page.origin).feed(at: page.url, credential: page.credential),
              let (entry, acquisition) = RemoteMemberResolution.opdsEntry(matching: server.remoteID, in: feed)
        else { return nil }
        return RemoteMemberResolution.enqueue(entry, using: acquisition, sourceID: server.sourceID, in: queue)
    }

    /// Forgets copies this made, deleting the files with them.
    ///
    /// Through the shared queue, for the same reason the keep above is: a removal ``store``
    /// wrote directly would be undone the next time any catalogue's own queue saved. Through
    /// `cancel`, because a member the keep queued from its catalogue can still be running.
    func forgetKept(_ ids: Set<String>, queue: DownloadQueue = .shared()) {
        for id in ids { queue.cancel(id) }
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
            DownloadStore.protect(destination)
            return Int64(size)
        }.value
    }

    /// Writes the record that makes the copy a download rather than a stray file.
    private func record(
        _ publication: Publication,
        from url: URL,
        bytes: Int64,
        in queue: DownloadQueue
    ) {
        // The copy would not exist without one; `copy` refuses before reaching here.
        guard let mediaType = publication.format.mediaType else { return }
        queue.record(
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
    }
}
