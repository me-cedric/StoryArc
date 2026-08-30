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
    public private(set) var library: DownloadLibrary

    /// The most recent failure, for a screen that wants to say something about it.
    public private(set) var lastFailure: String?

    private let client: OpdsClient
    private let store: DownloadStore?
    private let credential: (Download.ID) -> OpdsCredential?

    /// The origin of the catalogue this queue is downloading from.
    ///
    /// The bytes come through the background session rather than ``OpdsClient``, so the
    /// origin rule has to be applied here too: an acquisition href is a URL the *server*
    /// chose, and this queue is the one place in the app that carries a credential to one
    /// with nobody watching.
    private let origin: OpdsOrigin?

    /// The transfer for each running download, so it can be cancelled.
    private var running: [Download.ID: Task<Void, Never>] = [:]

    /// Callers waiting for a particular download to land, because they mean to open it.
    private var waiting: [Download.ID: [CheckedContinuation<URL?, Never>]] = [:]

    /// How the app decides whether the connection is one to be careful with.
    private let network = NetworkCost()

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

    private let settings: () -> AppSettings

    /// Where the bytes actually come from, so a backgrounded app keeps downloading.
    private let transfers: BackgroundTransfers

    /// Handed to the app so it can give the system its completion handler back.
    public var backgroundEvents: BackgroundTransfers { transfers }

    /// What is stopping the queue.
    public enum Held: Sendable, Equatable {
        case waitingForWifi
        case storageFull
    }

    /// Why the queue is not starting anything, if it is not.
    ///
    /// Nil when it may run. `offline-downloads` requires a held queue to *say* what it is
    /// waiting for — "waiting for Wi-Fi" and "the storage limit is reached" are different
    /// situations with different remedies, and a stalled list that explains neither is the
    /// worst of the three.
    public var held: Held? {
        let current = settings()
        if current.downloadOverWifiOnly, network.isCellular { return .waitingForWifi }
        guard let limit = current.maximumDownloadBytes else { return nil }
        return library.bytesOnDisk >= limit ? .storageFull : nil
    }

    /// Re-examines a held queue.
    ///
    /// Called when the network or the settings change. `offline-downloads` promises
    /// downloads "resume automatically when [Wi-Fi] returns", and automatically means
    /// without the reader going back to the screen.
    public func reconsider() { pump() }

    /// Which publications are recorded as being on the device.
    public var onDevice: Set<String> { Set(library.finished.map(\.id)) }

    /// Adds a download and starts it when there is room.
    public func enqueue(_ entry: OpdsEntry, using acquisition: OpdsAcquisition) {
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

    /// Enqueues, then waits for the file — for a reader who tapped to read it now.
    public func fetch(_ entry: OpdsEntry, using acquisition: OpdsAcquisition) async -> URL? {
        if let file = downloaded(entry) { return file }
        enqueue(entry, using: acquisition)
        return await withCheckedContinuation { continuation in
            waiting[entry.id, default: []].append(continuation)
        }
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
    private func pump() {
        // Held rather than cancelled: the queue keeps its order and its progress, and
        // starts again by itself the next time this is asked.
        guard held == nil else { return }
        let ready = library.downloads.filter { $0.state == .queued }
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
        var attempt = 0
        while !Task.isCancelled {
            attempt += 1
            if let file = await one(download, seriesHint: seriesHint) {
                running[download.id] = nil
                finish(download.id, with: file)
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
            // Not retryable. Fetching the same bytes again produces the same format.
            let message = if case let .unsupported(format) = error {
                String(
                    format: String(localized: "catalogue.acquire.unsupported", bundle: .module, locale: .storyArc),
                    format
                )
            } else {
                String(localized: "catalogue.acquire.unreadable", bundle: .module, locale: .storyArc)
            }
            fail(download.id, reason: message, retryable: false)
        } catch let error as OpdsError {
            fail(download.id, reason: CatalogueMessages.describe(error), retryable: error.isTransient)
        } catch {
            fail(download.id, reason: CatalogueMessages.reachability(error))
        }
        return nil
    }

    /// Moves a finished transfer into the download store and records it.
    ///
    /// Shared by the ordinary path and by adoption: a transfer that outlived the caller
    /// that asked for it has to end up in exactly the state one that did not would.
    private func land(
        _ download: Download,
        from temporary: URL,
        seriesHint: String? = nil
    ) async throws -> URL {
        guard let store else { throw CocoaError(.fileNoSuchFile) }
        try store.prepare()
        let file = store.location(of: download)
        // The download's own folder, not just the store's: the id is a directory now.
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: temporary, to: file)
        // Indexing *is* the verification. `offline-downloads` requires integrity to be
        // checked "before it is marked available offline", and with no checksum from the
        // server the honest check is whether the bytes are a publication this app can
        // open. A truncated archive fails here, not at the first page turn.
        _ = try await PublicationIndexer.index(fileAt: file, catalogueSeries: seriesHint)
        // The size comes from the file now rather than from a buffer, because the bytes
        // never passed through one: the system wrote them straight to disk.
        let written = Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        library = library
            .advancing(download.id, downloaded: written, expected: written)
            .marking(download.id, as: .finished)
        store.save(library)
        return file
    }

    private func fail(_ id: Download.ID, reason: String, retryable: Bool = true) {
        library = retryable
            ? library.failing(id, reason: reason)
            // Marked as though every attempt were spent, so the queue stops asking and the
            // reader sees the reason rather than a spinner that returns twice more.
            : library.marking(
                id,
                as: .failed(reason: reason, attempts: DownloadLibrary.attemptLimit)
            )
        if let store, let download = library[id] {
            // The whole directory, not the one file: a stem this build did not choose is
            // still this download's bytes, and leaving them is what made the storage total lie.
            store.remove(download)
        }
        store?.save(library)
        lastFailure = reason
    }

    /// Hands the result to whoever was waiting to read it.
    private func finish(_ id: Download.ID, with file: URL?) {
        for continuation in waiting.removeValue(forKey: id) ?? [] {
            continuation.resume(returning: file)
        }
    }
}
