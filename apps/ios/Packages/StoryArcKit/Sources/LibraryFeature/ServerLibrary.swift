import Catalogue
import Foundation
import Kavita
import Persistence
import Smb
import StoryArcCore

/// What the configured servers put in the library.
///
/// `library-browsing` requires one library over every source — "publications from every
/// configured source are shown together". A folder walk cannot reach a server, so this is
/// the other half of the answer.
///
/// **Nothing here ever removes a row.** Reconciliation deletes only from a source whose own
/// round covered it, and a server is in no round, so a server that refuses or answers
/// nothing costs a reader nothing. `sources`: "a failed refresh and an emptied source are
/// different things." Android's `ServerLibrary` is its twin.
enum ServerLibrary {

    /// Every server's slice, with the source each row came through.
    ///
    /// Per source, so one slow server does not hold up another. A source that throws
    /// contributes nothing and costs nothing.
    /// Every server's rows, and which sources held back more than they gave.
    struct Reading {
        var rows: [(Publication, UUID)] = []
        /// Sources whose read stopped at its own limit. ``SourceSlice`` explains that, and
        /// the source screen is what says it out loud.
        var partial: Set<UUID> = []
        /// Every genuine conflict a Kavita source's own pull found during this refresh.
        ///
        /// Task 2.9: this used to be `KavitaSync.pull`'s return value, thrown away the
        /// moment it came back — a refresh resolved the conflict (it still saves the merged
        /// record) but never told the reader one had happened, which is the one part of D3
        /// a background refresh could not skip.
        var conflicts: [KavitaConflict] = []
    }

    static func read(
        sources: [Source],
        credentials: CredentialStore?,
        progress: ProgressStore? = nil
    ) async -> Reading {
        var reading = Reading()
        for source in sources {
            let slice = await publications(
                of: source, credentials: credentials, progress: progress, conflicts: &reading.conflicts
            )
            reading.rows.append(contentsOf: slice.publications.map { ($0, source.id) })
            if slice.holdsMore { reading.partial.insert(source.id) }
        }
        return reading
    }

    private static func publications(
        of source: Source,
        credentials: CredentialStore?,
        progress: ProgressStore?,
        conflicts: inout [KavitaConflict]
    ) async -> SourceSlice {
        switch source.kind {
        case .kavitaServer:
            guard let page = KavitaPage(source: source, credentials: credentials) else { return .none }
            let client = KavitaClient(address: page.address)
            guard let fetched = try? await KavitaContributor.publications(source: source.id, client: client)
            else { return .none }
            // `reading-progress`: "when a synchronising source refreshes, progress
            // recorded on other devices is merged into the local store". This refresh
            // is that moment for every Kavita source, not only the one whose browser
            // the reader happens to have open — and it also flushes what an earlier,
            // offline session could not send. A genuine conflict is collected rather
            // than discarded, so the reader is told about it too (D3) — task 2.9.
            if let progress {
                conflicts += await KavitaSync.pull(
                    fetched.chapters,
                    in: KavitaProgressStore(),
                    into: progress,
                    of: source.id.uuidString,
                    to: page.address
                )
            }
            return fetched.slice

        case .opdsCatalog:
            guard let page = CataloguePage(source: source, credentials: credentials) else {
                return .none
            }
            let feed = try? await client(for: page).feed(at: page.url, credential: page.credential)
            guard let feed else { return .none }
            // The feed says so itself. A `next` link is the catalogue's own statement that
            // this page is not the whole of it.
            return SourceSlice(
                publications: feed.publications
                    .compactMap { OpdsContributor.publication(source: source.id, entry: $0) },
                holdsMore: feed.next != nil
            )

        case .networkShare:
            guard let page = SmbPage(source: source, credentials: credentials) else { return .none }
            return await SmbContributor.publications(
                source: source.id,
                client: SmbClient(address: page.address),
                address: page.address
            )

        // Already in the library: its files are what the scan walks.
        case .localFolder: return .none
        }
    }

    /// The client the OPDS branch of [publications] reads a catalogue with.
    ///
    /// 11.3: pulled out so a test can assert which pins reach it without a live catalogue.
    /// Built with no pins before, which silently failed every catalogue behind a certificate
    /// the reader had already pinned — `try?` turned the handshake refusal into `.none`, the
    /// same empty-slice answer a server that is merely offline gives, so nothing here ever
    /// said so. `CatalogueBrowser` and `DownloadQueue` did not have this bug because they
    /// already carry `pins`.
    static func client(for page: CataloguePage) -> OpdsClient {
        OpdsClient(pins: .app, origin: page.origin)
    }
}

extension LibraryModel {
    /// Every configured server's publications, adopted as a scanned file is.
    ///
    /// Adopted through the same `adopt(_:from:)` a walk uses, so a server's row and a
    /// folder's row are one kind of thing: same precedence, same identity, same grid.
    ///
    /// Here rather than in `LibraryScanning` because that file is at its 400-line cap, and
    /// this is where the reading it drives already lives.
    public func readServers() async {
        let reading = await ServerLibrary.read(
            sources: registry.sources,
            credentials: CredentialStore(),
            progress: progressStore
        )
        // A source already mid-continuation keeps its progress: a pull-to-refresh reads
        // page one again, and page one alone knows nothing past its own first slice —
        // replacing an entry already at page nine with a fresh "page two" would be the
        // continuation rewinding itself every time the reader pulls down.
        //
        // A source new to this process, but not new to the device, resumes from
        // `SourceReadProgressStore` instead — `sources`' *More from a source than the
        // library holds* asks for progress that survives a relaunch, not only a pull.
        let progressStore = SourceReadProgressStore()
        for sourceID in reading.partial where partialSources[sourceID] == nil {
            // Exact, not a guess: a page that reported `holdsMore` asked for at most its
            // kind's own limit and got a full page back, by ``SourceSlice``'s own rule.
            let firstSliceRead: Int
            switch registry.sources.first(where: { $0.id == sourceID })?.kind {
            case .kavitaServer: firstSliceRead = KavitaContributor.firstSlice
            case .networkShare: firstSliceRead = SmbContributor.firstSlice
            // A catalogue's first slice is one feed page, whatever size the server chose —
            // nothing here names that number, and nothing yet continues an OPDS read past
            // it, so there is no total to divide it into either.
            case .opdsCatalog, .localFolder, nil: firstSliceRead = 0
            }
            partialSources[sourceID] = .resuming(from: progressStore, source: sourceID, firstSliceRead: firstSliceRead)
        }
        // A source this read did not report partial has either finished — `land` already
        // cleared its own entry, store included — or is gone from the registry altogether;
        // either way nothing should keep asking disk about it.
        for sourceID in partialSources.keys where !reading.partial.contains(sourceID) {
            partialSources.removeValue(forKey: sourceID)
            progressStore.clear(for: sourceID)
        }
        RefreshConflicts.shared.report(reading.conflicts)
        for (publication, sourceID) in reading.rows {
            _ = adopt(publication, from: sourceID)
        }
        continueReadingServers()
        retryFailedKavitaSeries()
        guard !reading.rows.isEmpty else { return }
        // And written down, which nothing did: the snapshot was written when a *folder*
        // walk finished, so a reader whose library is one server and no folders had nothing
        // cached and opened the app offline to an empty shelf. A server's row has no file
        // behind it, so this is the only thing that carries it across a launch.
        //
        // It does not claim the shelf is fresh. This runs beside the folder walk, not
        // after it, so clearing the indicator here would answer for a walk that may still
        // be going — and one that met an unreadable directory has refreshed nothing.
        cacheLibrary(claimsFreshness: false)
    }

    /// Starts one background reader per Kavita source that is still partial.
    ///
    /// `sources`' *More from a source than the library holds*: the first slice is what
    /// ``readServers()`` above already reads; this is the rest of it, page by page, so the
    /// first screen paints from the slice and the library keeps growing underneath it
    /// rather than the reader waiting on a server with forty thousand series.
    ///
    /// SMB and OPDS are not here yet — `docs/delivery` names both as still to build.
    func continueReadingServers() {
        for source in registry.sources where source.kind == .kavitaServer {
            guard partialSources[source.id] != nil else { continue }
            guard let page = KavitaPage(source: source, credentials: CredentialStore()) else { continue }
            Task { await continueReadingKavita(source: source, client: KavitaClient(address: page.address)) }
        }
    }

    /// Reads one Kavita source's continuation until it finishes or a page refuses.
    ///
    /// **Stops and resumes cleanly when the source becomes unreachable.** A page that
    /// throws returns without touching ``partialSources``, so the very next call — another
    /// ``continueReadingServers()``, most often from the next ``readServers()`` — asks for
    /// the same page again rather than skipping it or losing the source's place.
    private func continueReadingKavita(source: Source, client: KavitaClient) async {
        let progressStore = SourceReadProgressStore()
        // Learned once and kept beside the read count for as long as the source stays
        // partial: an unfiltered listing is proven to answer the server's whole series list
        // in one request (see `KavitaClient.series`), so this costs one request for a
        // number the reader would otherwise never see until the read finished.
        if partialSources[source.id]?.total == nil, let all = try? await client.series() {
            partialSources[source.id]?.total = all.count
            if let updated = partialSources[source.id] { progressStore.record(updated.stored, for: source.id) }
        }
        let failedStore = KavitaFailedSeriesStore()
        await readOnward(
            progress: { partialSources[source.id] },
            fetch: { try? await KavitaContributor.page(source: source.id, client: client, page: $0) },
            land: { page, step in
                for publication in page.slice.publications { _ = adopt(publication, from: source.id) }
                if !page.failedSeriesIDs.isEmpty {
                    failedStore.record(failedStore.pending(for: source.id).union(page.failedSeriesIDs), for: source.id)
                }
                if case .continuing(let next) = step {
                    partialSources[source.id] = next
                    progressStore.record(next.stored, for: source.id)
                } else {
                    partialSources.removeValue(forKey: source.id)
                    progressStore.clear(for: source.id)
                }
                cacheLibrary(claimsFreshness: false)
            }
        )
    }

    /// Gives every Kavita series that failed an earlier page one more try, on every read
    /// rather than only while its source is still paging.
    ///
    /// A series can fail after its source's continuation has already finished — the page it
    /// was on reached the end and moved ``partialSources`` on — and ``continueReadingServers()``
    /// only drives a source that map still holds. Running here instead, from the same place
    /// that seeds a fresh continuation, means a failed series keeps getting asked for on
    /// every launch and every pull. Android's `retryFailedKavitaSeries` is the same function.
    func retryFailedKavitaSeries() {
        let failedStore = KavitaFailedSeriesStore()
        for source in registry.sources where source.kind == .kavitaServer {
            let pending = failedStore.pending(for: source.id)
            guard !pending.isEmpty, let page = KavitaPage(source: source, credentials: CredentialStore())
            else { continue }
            Task {
                let result = await KavitaContributor.retry(
                    source: source.id,
                    client: KavitaClient(address: page.address),
                    seriesIDs: pending
                )
                if !result.publications.isEmpty {
                    for publication in result.publications { _ = adopt(publication, from: source.id) }
                    cacheLibrary(claimsFreshness: false)
                }
                let stillFailed = Set(result.stillFailed)
                if stillFailed != pending { failedStore.record(stillFailed, for: source.id) }
            }
        }
    }
}
