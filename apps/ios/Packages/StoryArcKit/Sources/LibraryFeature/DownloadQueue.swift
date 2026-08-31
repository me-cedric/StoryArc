public import Foundation
public import Catalogue
internal import Formats
internal import Network
public import Persistence
public import StoryArcCore

/// The download queue: what is waiting, what is running, and what the reader can do to it.
///
/// `offline-downloads`' second requirement, which asks for "per-item and global pause,
/// resume, cancel" and for "a bounded number [to] run concurrently, and the bound ...
/// lowered on a metered connection".
///
/// Before this, a download was a blocking fetch in the foreground: tapping Download on a
/// four-hundred-megabyte comic meant waiting for it with no way to stop. Now a tap enqueues
/// and returns, and the queue does the waiting.
@Observable
@MainActor
public final class DownloadQueue {
    /// What has been downloaded and what is on its way.
    public internal(set) var library: DownloadLibrary

    /// The most recent failure, for a screen that wants to say something about it.
    public internal(set) var lastFailure: String?

    private let client: OpdsClient
    let store: DownloadStore?
    private let credential: (Download.ID) -> OpdsCredential?

    /// The origin of the catalogue this queue is downloading from.
    ///
    /// The bytes come through the background session rather than ``OpdsClient``, so the
    /// origin rule has to be applied here too: an acquisition href is a URL the *server*
    /// chose, and this queue is the one place in the app that carries a credential to one
    /// with nobody watching.
    private let origin: OpdsOrigin?

    /// The transfer for each running download, so it can be cancelled.
    var running: [Download.ID: Task<Void, Never>] = [:]

    /// Callers waiting for a particular download to land, because they mean to open it.
    var waiting: [Download.ID: [CheckedContinuation<URL?, Never>]] = [:]

    /// How the app decides whether the connection is one to be careful with.
    let network = NetworkCost()

    public init(
        pins: CertificatePins = CertificatePins(),
        store: DownloadStore? = nil,
        credential: @escaping (Download.ID) -> OpdsCredential? = { _ in nil },
        origin: OpdsOrigin? = nil,
        /// What the reader has asked of the queue.
        ///
        /// A closure rather than a value: `offline-downloads` requires a paused queue to
        /// "resume automatically when [Wi-Fi] returns", so the answer has to be re-asked
        /// rather than captured once at construction.
        settings: @escaping () -> AppSettings = { .defaults }
    ) {
        self.settings = settings
        self.origin = origin
        client = OpdsClient(pins: pins, origin: origin)
        transfers = BackgroundTransfers.shared(pins: pins)
        self.store = store
        self.credential = credential
        library = store?.library() ?? DownloadLibrary()
        // Anything that was mid-flight when the app died comes back queued, so the pump
        // picks it up rather than leaving it stuck at "in progress" for ever.
        pump()
        transfers.onOrphan { [weak self] name, file in
            Task { @MainActor in await self?.adopt(name, from: file) }
        }
        Task { await reclaim() }
    }

    /// Puts back anything the queue believes is running and nothing is.
    ///
    /// A completion can go missing — the process is killed, the transfer daemon drops the
    /// connection — and the download is then waiting on a callback that will never come,
    /// holding a concurrency slot for ever. The system's own list of tasks is the authority
    /// on what is actually in flight.
    public func reclaim() async {
        let carried = await transfers.outstanding().union(running.keys)
        library = library.reclaiming(carriedBy: carried)
        pump()
    }

    /// Takes in a transfer that finished with nothing waiting for it.
    private func adopt(_ id: Download.ID, from temporary: URL) async {
        guard let download = library[id],
              let file = try? await land(download, from: temporary)
        else {
            try? FileManager.default.removeItem(at: temporary)
            return
        }
        running[id] = nil
        finish(id, with: file)
        pump()
    }

    /// How many transfers run at once.
    ///
    /// Two on an ordinary connection: enough that a slow server does not stall the whole
    /// queue, few enough that a reader's bandwidth is not divided six ways. One on a
    /// metered or constrained connection, which is what `offline-downloads` means by
    /// lowering the bound — Low Data Mode and a personal hotspot both land here.
    public var concurrency: Int { network.isCareful ? 1 : 2 }

    let settings: () -> AppSettings

    /// Where the bytes actually come from, so a backgrounded app keeps downloading.
    private let transfers: BackgroundTransfers

    /// Handed to the app so it can give the system its completion handler back.
    public var backgroundEvents: BackgroundTransfers { transfers }

    /// Whether the volume was short of room the last time it was asked.
    ///
    /// Cached rather than asked on demand: ``held`` is read from a view body, and a
    /// filesystem stat per render is a cost a screen should not pay. Refreshed wherever the
    /// queue is about to act — which is the only moment the answer changes anything.
    ///
    /// Here rather than beside the rest of the shortage in ``DownloadQueueHolds``, because
    /// a stored property cannot be declared in an extension.
    var spaceIsLow = false

    /// Whether the cover cache has already been given up for this shortage.
    ///
    /// `offline-downloads` evicts it "before any downloaded publication", and once is
    /// enough: re-clearing an empty cache on every pump would be work that frees nothing
    /// and hides the fact that the eviction did not help.
    var coversEvicted = false

    /// Which publications are recorded as being on the device.
    public var onDevice: Set<String> { Set(library.finished.map(\.id)) }

    /// Adds a download and starts it when there is room.
    ///
    /// - Parameter overridingMeteredConnection: the reader was asked whether to spend
    ///   mobile data on this one, and said yes. `offline-downloads` grants that "for that
    ///   item only", which is why it is recorded against the id rather than flipping a
    ///   setting — see ``MeteredDownload``.
    public func enqueue(
        _ entry: OpdsEntry,
        using acquisition: OpdsAcquisition,
        overridingMeteredConnection: Bool = false
    ) {
        if overridingMeteredConnection { overridden.insert(entry.id) }
        library = library.queueing(
            Download(
                id: entry.id,
                title: entry.title,
                remote: acquisition.href,
                mediaType: acquisition.mediaType
            )
        )
        titles[entry.id] = entry
        store?.save(library)
        pump()
    }

    /// The publications the reader has agreed to spend mobile data on.
    ///
    /// In memory only, and deliberately: `offline-downloads` grants the override for one
    /// item, at one moment, on one connection. A grant that outlived the app would be a
    /// standing permission the reader never gave.
    var overridden: Set<Download.ID> = []

    /// Enqueues, then waits for the file — for a reader who tapped to read it now.
    ///
    /// A reader who pressed *Read* on a metered link has explicitly asked for this one
    /// publication, which is exactly the override `offline-downloads` describes — so the
    /// confirmation is the caller's to have already presented, and the grant travels with
    /// the call rather than being asked for twice.
    public func fetch(
        _ entry: OpdsEntry,
        using acquisition: OpdsAcquisition,
        overridingMeteredConnection: Bool = false
    ) async -> URL? {
        if let file = downloaded(entry) { return file }
        enqueue(
            entry,
            using: acquisition,
            overridingMeteredConnection: overridingMeteredConnection
        )
        // `offline-downloads`' *Reading while downloading*. The reader is waiting on this
        // one, so it goes to the head of the queue rather than behind whatever they lined
        // up earlier and are not reading — on a metered link, where the bound is one, that
        // was the difference between a five-megabyte comic and a four-hundred-megabyte wait.
        promote(entry.id)
        return await withCheckedContinuation { continuation in
            waiting[entry.id, default: []].append(continuation)
        }
    }

    /// Puts a download at the head of the queue.
    ///
    /// The order is the reader's — `offline-downloads` gives them pause, resume, cancel and
    /// reorder — and this is that reorder asked for by opening a book. The rule about what
    /// "head" means among running and finished downloads is
    /// ``DownloadLibrary/promoting(_:)``'s, and is asserted rather than living here.
    public func promote(_ id: Download.ID) {
        let ahead = library.promoting(id)
        guard ahead != library else { return }
        library = ahead
        store?.save(library)
        pump()
    }

    /// Stops a download and forgets it, deleting whatever arrived.
    public func cancel(_ id: Download.ID) {
        running[id]?.cancel()
        running[id] = nil
        remove(id)
        finish(id, with: nil)
        pump()
    }

    /// Holds a download where it is. The reader asked, so the reason says so.
    public func pause(_ id: Download.ID) {
        running[id]?.cancel()
        running[id] = nil
        library = library.marking(id, as: .paused(.byReader))
        store?.save(library)
        finish(id, with: nil)
        pump()
    }

    /// Puts a paused or failed download back in the queue.
    public func resume(_ id: Download.ID) {
        guard library[id] != nil else { return }
        library = library.marking(id, as: .queued)
        store?.save(library)
        pump()
    }

    /// Moves a download in the queue, which is the order it will be worked through.
    public func move(_ id: Download.ID, to destination: Int) {
        library = library.moving(id, to: destination)
        store?.save(library)
    }

    /// Where a publication already downloaded lives, if it does.
    ///
    /// Asked of the filesystem: a download the system reclaimed is one the reader should be
    /// offered again rather than shown a missing file.
    public func downloaded(_ entry: OpdsEntry) -> URL? {
        guard let download = library[entry.id], download.state.isFinished, let store else {
            return nil
        }
        let file = store.location(of: download)
        return FileManager.default.fileExists(atPath: file.path()) ? file : nil
    }

    /// Forgets a download and deletes its file.
    public func remove(_ id: Download.ID) {
        library = store?.removing(id, from: library) ?? library.removing(id)
    }

    /// What each queued download is *of*, so a retry has an entry to index against.
    ///
    /// Held here rather than on ``Download`` because it is a catalogue's idea of a
    /// publication, and the download record is meant to outlive the page it came from.
    private var titles: [Download.ID: OpdsEntry] = [:]

    /// Starts whatever should be running and is not.
    func pump() {
        refreshHeadroom()
        if spaceIsLow {
            holdForSpace()
            return
        }
        releaseSpaceHolds()
        // Held rather than cancelled: the queue keeps its order and its progress, and
        // starts again by itself the next time this is asked.
        //
        // The reader's own storage maximum stops everything, because an override is about
        // the *connection* and says nothing about the disk. Waiting for Wi-Fi is decided
        // per download instead — `offline-downloads` grants the override "for that item
        // only", so one granted publication may run while the rest of the queue waits.
        if held == .storageFull { return }
        let ready = library.downloads.filter { $0.state == .queued && mayStart($0) }
        for download in ready.prefix(max(0, concurrency - running.count)) {
            // No catalogue entry is needed to fetch one: the record carries the address, the
            // media type and the name. An entry enqueued by a previous launch is gone from
            // `titles`, and a download that only resumes while the app that started it is
            // still alive is not the offline promise `offline-downloads` makes.
            start(download, seriesHint: titles[download.id]?.series)
        }
    }

    private func start(_ download: Download, seriesHint: String?) {
        library = library.marking(download.id, as: .running)
        running[download.id] = Task { [weak self] in
            await self?.transfer(download, seriesHint: seriesHint)
        }
    }

    private func transfer(_ download: Download, seriesHint: String?) async {
        while !Task.isCancelled {
            if let file = await one(download, seriesHint: seriesHint) {
                running[download.id] = nil
                finish(download.id, with: file)
                pump()
                return
            }
            // `offline-downloads`: "a failed verification re-queues it once". The bytes
            // arrived and were not a book, so ``one(_:seriesHint:)`` put the download back
            // in the queue rather than failing it. Left there for the pump to start again,
            // and — the part that matters — nobody waiting to *read* it is told it failed,
            // because it has not.
            if library[download.id]?.state == .queued {
                running[download.id] = nil
                pump()
                return
            }
            guard let failed = library[download.id], DownloadLibrary.shouldRetry(failed),
                  case let .failed(_, attempts) = failed.state
            else { break }
            try? await Task.sleep(for: DownloadLibrary.backoff(afterAttempts: attempts))
        }
        running[download.id] = nil
        finish(download.id, with: nil)
        pump()
    }

    /// One attempt, with no opinion about whether there will be another.
    private func one(
        _ download: Download,
        seriesHint: String?
    ) async -> URL? {
        do {
            // Through the background session rather than an ordinary request:
            // `offline-downloads` wants a backgrounded transfer to continue "as far as the
            // platform allows", and on iOS that is what allows it.
            // The same rule ``OpdsClient`` applies, because this is the same kind of
            // address: one the catalogue chose. An acquisition href off the source's own
            // origin is fetched without the credential, and one that steps down to
            // cleartext is not fetched at all.
            guard OpdsOrigin.isFetchable(download.remote) else { throw OpdsError.refusedAddress }
            let home = origin ?? OpdsOrigin(url: download.remote)
            if home?.downgrades(download.remote) == true { throw OpdsError.refusedAddress }

            var request = URLRequest(url: download.remote)
            if let credential = credential(download.id), home?.admits(download.remote) == true {
                request.setValue(credential.header, forHTTPHeaderField: "Authorization")
            }
            let temporary = try await transfers.download(request, named: download.id)
            return try await land(download, from: temporary, seriesHint: seriesHint)
        } catch let error as PublicationIndexer.IndexError {
            // Indexing *is* the verification, so this is where `offline-downloads`' "a
            // failed verification re-queues it once" is answered — and the two ways it can
            // fail get different answers.
            //
            // **An unsupported format is not a failed verification.** The bytes are
            // exactly what the server holds; the app simply has no decoder for them.
            // Fetching them again produces the same format, so this is terminal and always
            // was.
            //
            // **Unreadable bytes are a failed verification.** A truncated archive, a
            // central directory that is not there, a file that stops mid-entry — the
            // likeliest cause is the transfer rather than the publication, and one more
            // fetch is the cheapest way to find out. Exactly one: a second identical
            // result is the server's answer, and asking a third time is asking a question
            // already answered twice.
            if case let .unsupported(format) = error {
                fail(
                    download.id,
                    reason: String(
                        format: String(
                            localized: "catalogue.acquire.unsupported",
                            bundle: .module,
                            locale: .storyArc
                        ),
                        format
                    ),
                    retryable: false
                )
            } else {
                failVerification(
                    download.id,
                    reason: String(
                        localized: "catalogue.acquire.unreadable",
                        bundle: .module,
                        locale: .storyArc
                    )
                )
            }
        } catch let error as OpdsError {
            fail(download.id, reason: CatalogueMessages.describe(error), retryable: error.isTransient)
        } catch {
            fail(download.id, reason: CatalogueMessages.reachability(error))
        }
        return nil
    }
}
