public import Foundation

public import Catalogue
public import Persistence
public import StoryArcCore

/// The one app-level queue every screen writes through, and what a screen without one may
/// still ask of the download store.
///
/// **The bug this closes.** A catalogue page built its own ``DownloadQueue``, so two pages
/// open at once — or a page and the Downloads destination, which held no queue and wrote
/// ``DownloadStore`` directly — each carried a different in-memory copy of the same record
/// set. Whichever one saved last won: a *Stop* on one page's row did not reach the transfer
/// a different page's queue was running, a Kavita keep or a source removal written straight
/// to the store was overwritten the next time any catalogue's queue pumped, and Android's
/// `DownloadQueue.enqueue` overwrote a reorder the same way. `offline-downloads` 1.1 makes
/// this queue the *only* writer: every screen reads and writes through it, and there is
/// exactly one of it for the life of the process.
///
/// **Multiple sources, one queue.** A single queue now runs downloads for every catalogue at
/// once, so nothing here may be fixed to one source the way a per-page queue's own `origin`
/// and `sourceID` were. ``DownloadQueue/enqueue(_:using:sourceID:overridingMeteredConnection:)``
/// and its neighbours take the source explicitly instead, from the page that knows it, and
/// the credential closure below resolves a transfer's source from the record itself rather
/// than from the queue that is running it — the same source-keyed lookup
/// `LibraryFeature/SourceRangeTransport` uses for a streamed read.
extension CertificatePins {
    /// The app's one pin set: every certificate a reader has accepted, loaded from the store
    /// once and shared by every connection that can reach a source.
    ///
    /// One instance, because a pin accepted while adding a server must be trusted at once by
    /// the download queue, the background session and a streamed read. A separate copy of
    /// the store keeps the set it loaded, so a new pin reaches it only after a relaunch.
    public static let app = CertificatePins(CertificatePinStore().pins())
}

extension DownloadQueue {
    private static var instance: DownloadQueue?

    /// The shared queue, built once and reused.
    ///
    /// Every parameter is read fresh from disk on every call the closure makes rather than
    /// captured from whatever view happened to build the queue first — `sources` re-asks
    /// `SourceStore`, and the credential closure re-asks `CredentialStore` — so it does not
    /// matter which caller's parameters "win" the way it does for
    /// `Catalogue/BackgroundTransfers/shared(pins:)`: a page that calls this with no
    /// arguments at all still resolves every source's own credential correctly.
    ///
    /// - Parameter pins: the app-wide set, every host a reader has ever pinned — see
    ///   ``SourceRangeTransport``, which reads the same store the same way for the same
    ///   reason.
    /// - Parameter store: the real download store by default. A test that wants a shared
    ///   queue of its own — proving the singleton mechanics without touching
    ///   `UserDefaults.standard` — passes one built over a fresh defaults suite, together
    ///   with ``resetShared()`` between tests.
    @MainActor
    public static func shared(
        pins: CertificatePins = .app,
        store: DownloadStore = DownloadStore(),
        sources: @escaping @Sendable () -> [Source] = { SourceStore().registry().sources },
        credentials: CredentialStore? = CredentialStore(),
        settings: @escaping () -> AppSettings = SettingsStore().settings
    ) -> DownloadQueue {
        if let instance { return instance }
        // dl-core 1.2: a record from before source-keyed ids is re-keyed here, because this
        // is the only queue the app builds and it has no single origin to match against.
        DownloadMigration.migratingStrays(in: store, sources: sources())
        let queue = DownloadQueue(
            pins: pins,
            store: store,
            credential: Self.credentialResolver(store: store, sources: sources, credentials: credentials),
            settings: settings
        )
        instance = queue
        return queue
    }

    /// A transfer's credential, resolved from the record's own source rather than from a
    /// single source fixed on the queue.
    ///
    /// **Also where this queue keeps the promise its own `origin?.admits(url)` check no
    /// longer can.** `DownloadQueueTransfer.one()` derives `home` from `download.remote`
    /// itself whenever the queue's `origin` is nil — true for this queue always, now that
    /// it runs every source at once — so `home.admits(download.remote)` compares a value
    /// against itself and is never false. Refusing here, before a credential is even
    /// looked up, unless the record's *own* source really is configured at the address the
    /// record is about to be fetched from, is what keeps `sources`' "data leaves the device
    /// only to the sources the user configured" true for a shared queue.
    ///
    /// A fresh `store` read rather than `self.library`: this closure is built before the
    /// queue that will call it exists, so it cannot capture the queue, and asking disk once
    /// per attempted transfer is the cost of a queue that is no longer one page's own.
    static func credentialResolver(
        store: DownloadStore,
        sources: @escaping @Sendable () -> [Source],
        credentials: CredentialStore?
    ) -> (Download.ID) -> OpdsCredential? {
        { id in
            guard let download = store.library()[id],
                  let sourceID = download.sourceID,
                  let source = sources().first(where: { $0.id == sourceID }),
                  let locator = source.locator, let home = URL(string: locator),
                  let sourceOrigin = OpdsOrigin(url: home),
                  sourceOrigin.admits(download.remote)
            else { return nil }
            return source.credentialReference
                .flatMap { credentials?.secret(for: $0) }
                .flatMap(OpdsCredential.init(stored:))
        }
    }

    /// Test-only: drops the shared instance, so each test builds its own rather than
    /// inheriting whichever test ran first.
    static func resetShared() { instance = nil }
}

/// What a screen with no transfer to run may still do to the shared queue's record set —
/// reorder, record a copy that landed some other way, remove a finished download, undo that
/// removal, or take a source's downloads with it. Split out of ``DownloadQueue`` because
/// that file is at the 400-line cap this project enforces.
extension DownloadQueue {
    /// Moves a queued download one place earlier or later — the write behind the Downloads
    /// destination's reorder control.
    ///
    /// Through the queue's own cached ``library`` rather than a fresh `DownloadStore` read,
    /// so a reorder is not itself the write a running pump's next save overwrites.
    public func reorder(_ id: Download.ID, later: Bool) {
        library = library.moving(id, later: later)
        store?.save(library)
    }

    /// Records a completed copy that arrived by some route other than this queue's own
    /// transfer — a Kavita keep, or a local file copied straight in.
    ///
    /// ``StoryArcCore/DownloadLibrary/queueing(_:)`` is a no-op once the id is already
    /// known, exactly as it is for an ordinary enqueue: this does not re-copy a publication
    /// the reader already has.
    public func record(_ download: Download) {
        library = library.queueing(download)
        store?.save(library)
    }

    /// Takes a finished publication's download off the device, reversibly. See
    /// `Persistence/RemovedDownload`.
    public func removeAfterFinishing(_ id: Download.ID) -> RemovedDownload? {
        guard let store, let outcome = store.removeAfterFinishing(id, from: library) else {
            return nil
        }
        library = outcome.library
        return outcome.removed
    }

    /// Puts a removed download back — the Downloads destination's undo.
    public func restore(_ removed: RemovedDownload) {
        guard let store else { return }
        library = removed.undo(library, in: store)
    }

    /// Forgets every download a source contributed, deleting the files, for when the source
    /// itself is removed.
    @discardableResult
    public func removingAll(from sourceID: UUID) -> [Download] {
        let (kept, removed) = library.removingAll(from: sourceID)
        for download in removed { store?.remove(download) }
        library = kept
        store?.save(library)
        return removed
    }
}
