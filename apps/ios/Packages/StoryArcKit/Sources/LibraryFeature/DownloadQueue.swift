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

    let client: OpdsClient
    let store: DownloadStore?
    let credential: (Download.ID) -> OpdsCredential?

    /// The origin of the catalogue this queue is downloading from.
    ///
    /// The bytes come through the background session rather than ``OpdsClient``, so the
    /// origin rule has to be applied here too: an acquisition href is a URL the *server*
    /// chose, and this queue is the one place in the app that carries a credential to one
    /// with nobody watching.
    let origin: OpdsOrigin?

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
        /// What the reader has asked of the queue, re-asked rather than captured.
        ///
        /// `offline-downloads` resumes a held queue "automatically when [Wi-Fi] returns", so
        /// the answer cannot be a value taken once. Required rather than defaulted, because
        /// the caller that omitted the old default shipped a queue that was never held.
        settings: @escaping () -> AppSettings
    ) {
        self.settings = settings
        self.origin = origin
        client = OpdsClient(pins: pins, origin: origin)
        transfers = BackgroundTransfers.shared(pins: pins)
        self.store = store
        self.credential = credential
        library = store?.library() ?? DownloadLibrary()
        // So a retry pressed on a screen that owns no queue can reach this one while it is
        // alive — see `DownloadQueueRetry.swift`.
        remember()
        // The monitor's own update handler is `offline-downloads`' "automatically". Weakly,
        // because the queue owns the monitor and a strong capture would be a cycle.
        network.onChange = { [weak self] in self?.reconsider() }
        // Anything that was mid-flight when the app died comes back queued, so the pump
        // picks it up rather than leaving it stuck at "in progress" for ever. A record the
        // Downloads screen put back in the queue while no queue was alive is picked up here
        // for the same reason and by the same line.
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

    let settings: () -> AppSettings

    /// Where the bytes actually come from, so a backgrounded app keeps downloading.
    let transfers: BackgroundTransfers

    /// Handed to the app so it can give the system its completion handler back.
    public var backgroundEvents: BackgroundTransfers { transfers }

    /// Whether the volume was short of room the last time it was asked.
    ///
    /// Asked once per ``pump()`` rather than wherever the answer is wanted: it is a
    /// filesystem stat on the main actor, and the only moment it changes anything is the
    /// moment the queue is about to act. What a screen draws is ``held``, which reads the
    /// records this decision wrote and asks the volume nothing.
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
    ///
    /// Then looks again, because room was freed. Deleting a finished publication is the one
    /// remedy `offline-downloads` names for a queue held by the storage limit, and a remedy
    /// that needs the reader to leave the screen and come back is not one.
    public func remove(_ id: Download.ID) {
        library = store?.removing(id, from: library) ?? library.removing(id)
        pump()
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
        // Waiting for Wi-Fi is decided per download — `offline-downloads` grants the
        // override "for that item only", so one granted publication may run while the rest
        // of the queue waits — and it is decided in both directions here, which is what
        // stops a transfer the connection no longer permits.
        holdForConnection()
        // The reader's own storage maximum stops everything, because an override is about
        // the *connection* and says nothing about the disk.
        if library.isAtLimit(settings().maximumDownloadBytes) { return }
        let ready = library.downloads.filter { $0.state == .queued && mayStart($0) }
        for download in ready.prefix(max(0, concurrency - running.count)) {
            // No catalogue entry is needed to fetch one: the record carries the address, the
            // media type and the name. An entry enqueued by a previous launch is gone from
            // `titles`, and a download that only resumes while the app that started it is
            // still alive is not the offline promise `offline-downloads` makes.
            start(download, seriesHint: titles[download.id]?.series)
        }
    }

}
