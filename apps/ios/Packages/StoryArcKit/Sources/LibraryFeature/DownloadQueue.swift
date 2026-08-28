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

    /// The transfer for each running download, so it can be cancelled.
    private var running: [Download.ID: Task<Void, Never>] = [:]

    /// Callers waiting for a particular download to land, because they mean to open it.
    private var waiting: [Download.ID: [CheckedContinuation<URL?, Never>]] = [:]

    /// How the app decides whether the connection is one to be careful with.
    private let network = NetworkCost()

    public init(
        pins: CertificatePins = CertificatePins(),
        store: DownloadStore? = nil,
        credential: @escaping (Download.ID) -> OpdsCredential? = { _ in nil }
    ) {
        client = OpdsClient(pins: pins)
        self.store = store
        self.credential = credential
        library = store?.library() ?? DownloadLibrary()
        // Anything that was mid-flight when the app died comes back queued, so the pump
        // picks it up rather than leaving it stuck at "in progress" for ever.
        pump()
    }

    /// How many transfers run at once.
    ///
    /// Two on an ordinary connection: enough that a slow server does not stall the whole
    /// queue, few enough that a reader's bandwidth is not divided six ways. One on a
    /// metered or constrained connection, which is what `offline-downloads` means by
    /// lowering the bound — Low Data Mode and a personal hotspot both land here.
    public var concurrency: Int { network.isCareful ? 1 : 2 }

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
        let file = store.location(
            for: entry.id,
            extension: DownloadStore.extension(for: download.mediaType)
        )
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
        let ready = library.downloads.filter { $0.state == .queued }
        for download in ready.prefix(max(0, concurrency - running.count)) {
            guard let entry = titles[download.id] else {
                // Enqueued by a previous launch, so nothing here knows what it was. Left
                // queued rather than failed: the reader can tap it again from the catalogue
                // and the record is already correct.
                continue
            }
            start(download, entry: entry)
        }
    }

    private func start(_ download: Download, entry: OpdsEntry) {
        library = library.marking(download.id, as: .running)
        running[download.id] = Task { [weak self] in
            await self?.transfer(download, entry: entry)
        }
    }

    private func transfer(_ download: Download, entry: OpdsEntry) async {
        let acquisition = OpdsAcquisition(
            href: download.remote,
            mediaType: download.mediaType,
            kind: .direct
        )
        var attempt = 0
        while !Task.isCancelled {
            attempt += 1
            if let file = await one(download, entry: entry, acquisition: acquisition) {
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
        entry: OpdsEntry,
        acquisition: OpdsAcquisition
    ) async -> URL? {
        do {
            let data = try await client.data(
                at: download.remote,
                credential: credential(download.id)
            )
            guard let store else { return nil }
            try store.prepare()
            let file = store.location(
                for: download.id,
                extension: DownloadStore.extension(for: download.mediaType)
            )
            try data.write(to: file, options: .atomic)
            // Indexing *is* the verification. `offline-downloads` requires integrity to be
            // checked "before it is marked available offline", and with no checksum from
            // the server the honest check is whether the bytes are a publication this app
            // can open. A truncated archive fails here, not at the first page turn.
            _ = try await PublicationIndexer.index(fileAt: file, seriesHint: entry.series)
            library = library
                .advancing(download.id, downloaded: Int64(data.count), expected: Int64(data.count))
                .marking(download.id, as: .finished)
            store.save(library)
            return file
        } catch let error as PublicationIndexer.IndexError {
            // Not retryable. Fetching the same bytes again produces the same format.
            let message = if case let .unsupported(format) = error {
                String(
                    format: String(localized: "catalogue.acquire.unsupported", bundle: .module),
                    format
                )
            } else {
                String(localized: "catalogue.acquire.unreadable", bundle: .module)
            }
            fail(download.id, reason: message, retryable: false)
        } catch let error as OpdsError {
            fail(download.id, reason: CatalogueMessages.describe(error), retryable: error.isTransient)
        } catch {
            fail(download.id, reason: CatalogueMessages.reachability(error))
        }
        return nil
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
            store.delete(
                store.location(for: id, extension: DownloadStore.extension(for: download.mediaType))
            )
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

/// Which acquisition to take, and which the reader could choose instead.
///
/// Its own type because the question is about a *catalogue entry*, not about the queue: the
/// grid asks it to decide whether a cell is tappable, long before anything is downloaded.
public enum CatalogueAcquisition {
    /// `opds-catalog`: "the app selects EPUB for reflowable reading and lets the user choose
    /// another format". EPUB first, then the comic containers, then PDF — a comic offered as
    /// both CBZ and PDF is a comic, and the PDF is a worse copy of it.
    public static func best(of entry: OpdsEntry) -> OpdsAcquisition? {
        readable(in: entry).min { rank($0) < rank($1) }
    }

    /// Every acquisition this app could act on, in the order the feed listed them.
    public static func readable(in entry: OpdsEntry) -> [OpdsAcquisition] {
        entry.acquisitions.filter { acquisition in
            guard acquisition.kind.isFetchable else { return false }
            return PublicationFormat(mediaType: acquisition.mediaType)?.isOpenable == true
        }
    }

    private static func rank(_ acquisition: OpdsAcquisition) -> Int {
        switch PublicationFormat(mediaType: acquisition.mediaType) {
        case .epub: 0
        case .cbz, .cbt, .cbr: 1
        case .pdf: 2
        default: 3
        }
    }
}

/// Whether the connection is one to be careful with.
///
/// `offline-downloads`: the bound is "lowered on a metered connection", and "when the
/// platform's data saver or Low Data Mode is active ... the app treats the connection as
/// metered regardless of its own setting". `isConstrained` is Low Data Mode; `isExpensive`
/// is cellular and personal hotspot. Both mean the same thing here: use less of it.
@MainActor
final class NetworkCost {
    private let monitor = NWPathMonitor()
    private var path: NWPath?

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.path = path }
        }
        monitor.start(queue: .global(qos: .utility))
    }

    deinit {
        monitor.cancel()
    }

    /// True until the monitor has an answer, which errs toward using less.
    var isCareful: Bool {
        guard let path else { return true }
        return path.isConstrained || path.isExpensive
    }
}
