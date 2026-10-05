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
    ///
    /// The reason rather than the sentence — `localization` 15.9 — so a screen draws it
    /// through ``DownloadFailureWords`` in whichever language the reader has chosen now.
    public internal(set) var lastFailure: DownloadFailure?

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

    /// The origin of the source a record names, for a queue with no ``origin`` of its own.
    ///
    /// The shared queue runs every catalogue at once, so the rule above has to come from
    /// the record's own source. Without it, the origin is the download address itself, and
    /// an `https` catalogue could send its books over cleartext.
    let sourceOrigin: (UUID) -> OpdsOrigin?

    /// The source this catalogue belongs to, so an enqueued download can be keyed against
    /// the catalogue it came from rather than its raw entry id alone.
    ///
    /// `offline-downloads`' *OPDS downloads are keyed by the raw entry id* (dl-core 1.2):
    /// two catalogues that number their entries the same way shared one record and one
    /// file. Optional, and defaulted to `nil`, so a queue built without a source — a host
    /// test, mostly — keeps the old, unscoped id rather than refusing to run.
    public let sourceID: UUID?

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
        sourceOrigin: @escaping (UUID) -> OpdsOrigin? = { _ in nil },
        sourceID: UUID? = nil,
        /// What the reader has asked of the queue, re-asked rather than captured.
        ///
        /// `offline-downloads` resumes a held queue "automatically when [Wi-Fi] returns", so
        /// the answer cannot be a value taken once. Required rather than defaulted, because
        /// the caller that omitted the old default shipped a queue that was never held.
        settings: @escaping () -> AppSettings
    ) {
        self.settings = settings
        self.origin = origin
        self.sourceOrigin = sourceOrigin
        self.sourceID = sourceID
        client = OpdsClient(pins: pins, origin: origin)
        transfers = BackgroundTransfers.shared(pins: pins)
        self.store = store
        self.credential = credential
        // A stray pre-1.2 record is re-keyed before this read, by the shared queue's own
        // construction. See `DownloadMigration.migratingStrays(in:sources:)`.
        library = store?.library() ?? DownloadLibrary()
        // The monitor's own update handler is `offline-downloads`' "automatically". Weakly,
        // because the queue owns the monitor and a strong capture would be a cycle.
        network.onChange = { [weak self] in self?.reconsider() }
        // Anything that was mid-flight when the app died comes back queued, so the pump
        // picks it up rather than leaving it stuck at "in progress" for ever.
        pump()
        transfers.onOrphan { [weak self] name, file in
            Task { @MainActor in await self?.adopt(name, from: file) }
        }
        transfers.onResumable { [weak self] name, data in
            Task { @MainActor in self?.keep(data, for: name) }
        }
        transfers.onProgress { [weak self] name, written, expected in
            Task { @MainActor in self?.advance(name, written: written, expected: expected) }
        }
        transfers.onAttempt { [weak self] name, resumed in
            Task { @MainActor in self?.noteAttempt(name, resumed: resumed) }
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

    /// The id a download of this entry is recorded under.
    ///
    /// Namespaced by source when one is known, as Kavita already keys a chapter — see
    /// `KavitaKeep`. Without a source the raw entry id stands, which keeps a queue built
    /// with none (a host test, mostly) working exactly as it did.
    ///
    /// - Parameter sourceID: the catalogue page's own source, when this queue is the one
    ///   ``DownloadQueue/shared(pins:sources:credentials:settings:)`` hands out to every
    ///   page at once. `nil` — the default — falls back to the queue's own ``sourceID``,
    ///   which is what a queue built for a single catalogue (a host test, mostly) still
    ///   carries.
    public func downloadID(for entryID: String, sourceID: UUID? = nil) -> Download.ID {
        guard let effective = sourceID ?? self.sourceID else { return entryID }
        return RemoteMemberResolution.downloadID(entry: entryID, sourceID: effective)
    }

    /// Whether this entry already has a finished download.
    public func isOnDevice(_ entryID: String, sourceID: UUID? = nil) -> Bool {
        onDevice.contains(downloadID(for: entryID, sourceID: sourceID))
    }

    /// Adds a download and starts it when there is room.
    ///
    /// - Parameter sourceID: the catalogue page's own source. `nil` falls back to the
    ///   queue's own ``sourceID``, exactly as ``downloadID(for:sourceID:)`` does — see it
    ///   for why.
    /// - Parameter overridingMeteredConnection: the reader was asked whether to spend
    ///   mobile data on this one, and said yes. `offline-downloads` grants that "for that
    ///   item only", which is why it is recorded against the id rather than flipping a
    ///   setting — see ``MeteredDownload``.
    public func enqueue(
        _ entry: OpdsEntry,
        using acquisition: OpdsAcquisition,
        sourceID: UUID? = nil,
        overridingMeteredConnection: Bool = false
    ) {
        let effective = sourceID ?? self.sourceID
        let id = downloadID(for: entry.id, sourceID: effective)
        if overridingMeteredConnection { overridden.insert(id) }
        library = library.queueing(
            Download(
                id: id,
                sourceID: effective,
                title: entry.title,
                remote: acquisition.href,
                mediaType: acquisition.mediaType,
                expectedBytes: acquisition.length
            )
        )
        hints[id] = entry.series
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
        sourceID: UUID? = nil,
        overridingMeteredConnection: Bool = false
    ) async -> URL? {
        if let file = downloaded(entry, sourceID: sourceID) { return file }
        let id = downloadID(for: entry.id, sourceID: sourceID)
        switch library[id]?.state {
        case .failed, .paused(.byReader):
            // `enqueue` is a no-op once a publication is already known, and neither state
            // resolves itself: a failed download has no attempts left, and a download the
            // reader paused stays paused until asked. A reader pressing Read on either is
            // that ask — without this, the continuation below waits on a transfer nothing
            // is ever going to start.
            if overridingMeteredConnection { overridden.insert(id) }
            hints[id] = entry.series
            resume(id)
        default:
            enqueue(
                entry,
                using: acquisition,
                sourceID: sourceID,
                overridingMeteredConnection: overridingMeteredConnection
            )
        }
        // `offline-downloads`' *Reading while downloading*. The reader is waiting on this
        // one, so it goes to the head of the queue rather than behind whatever they lined
        // up earlier and are not reading — on a metered link, where the bound is one, that
        // was the difference between a five-megabyte comic and a four-hundred-megabyte wait.
        promote(id)
        return await withCheckedContinuation { continuation in
            waiting[id, default: []].append(continuation)
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
    public func downloaded(_ entry: OpdsEntry, sourceID: UUID? = nil) -> URL? {
        file(of: downloadID(for: entry.id, sourceID: sourceID))
    }

    /// Forgets a download and deletes its file.
    ///
    /// Then looks again, because room was freed. Deleting a finished publication is the one
    /// remedy `offline-downloads` names for a queue held by the storage limit, and a remedy
    /// that needs the reader to leave the screen and come back is not one.
    public func remove(_ id: Download.ID) {
        library = store?.removing(id, from: library) ?? library.removing(id)
        given[id] = nil
        pump()
    }

    /// The series each queued download belongs to, so the indexer can name one.
    ///
    /// Held here rather than on ``Download`` because it is a catalogue's idea of a
    /// publication, and the download record is meant to outlive the page it came from. The
    /// whole ``OpdsEntry`` used to be kept and only its series was ever read.
    var hints: [Download.ID: String] = [:]

    /// A credential handed in at enqueue, for a source whose secret is not the credential.
    ///
    /// `offline-downloads` 1.9: Kavita mints a short-lived bearer token from the reader's
    /// API key, and ``credentialResolver(store:sources:credentials:)`` reads the secure
    /// store, which holds the key. So the caller that already has an authenticated client
    /// hands the token in with the chapter. In memory only, for the reason ``overridden``
    /// is: a session token written down is a secret outliving the session that minted it.
    var given: [Download.ID: OpdsCredential] = [:]

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
            // `hints`, and a download that only resumes while the app that started it is
            // still alive is not the offline promise `offline-downloads` makes.
            start(download, seriesHint: hints[download.id])
        }
    }

}
