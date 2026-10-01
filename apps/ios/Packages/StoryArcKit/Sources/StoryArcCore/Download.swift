public import Foundation

/// A publication taken from a remote source and kept on the device.
///
/// `offline-downloads` is about "taking a library with you", and the first thing that
/// requires is a record: what was fetched, from where, how big it is, and whether it is
/// finished. Without one, a fetched file is a file in a cache directory that nothing can
/// list, attribute, or remove — which is exactly what the catalogue's first cut produced.
public struct Download: Sendable, Identifiable, Equatable {
    /// The publication's stable identity, so a download and a library row are the same
    /// thing seen twice rather than two rows that happen to share a title.
    public let id: String

    /// Which source it came from, for the storage view's per-source breakdown and so
    /// removing a source can take its downloads with it.
    public let sourceID: UUID?

    public let title: String

    /// Where it came from, so a failed download can be retried without re-browsing.
    public let remote: URL

    public let mediaType: String

    public var state: State

    /// What the server said the whole thing weighs, when it said. `nil` when it did not:
    /// `offline-downloads` requires a size to be *shown*, and a fabricated one is worse
    /// than an honest blank.
    public var expectedBytes: Int64?

    /// What is on disk now.
    public var downloadedBytes: Int64

    public var completedAt: Date?

    /// How many times the bytes arrived and were not a publication this app could open.
    ///
    /// `offline-downloads`: "its integrity is verified before it is marked available
    /// offline, and a failed verification re-queues it once". Counted separately from the
    /// attempts on ``State/failed(reason:attempts:)`` because the two failures are not the
    /// same event and do not get the same number of chances: a transfer that never arrived
    /// is worth three tries, and a transfer that arrived corrupt is worth exactly one more
    /// — the second identical result is the server's answer, not the network's.
    ///
    /// On the record rather than in the queue, so it survives the app being killed between
    /// the first corrupt download and the second.
    public var verificationFailures: Int

    /// Whether the transfer that produced what is on disk now carried on from an earlier
    /// one, or started over.
    ///
    /// `offline-downloads`' *Resuming after interruption* builds both outcomes and says
    /// neither: the reader is never told which one happened. `nil` is a transfer that has
    /// never been interrupted — a first attempt is neither a resume nor a restart, and
    /// saying so would be the noise every other conditional row in this app avoids.
    public var lastAttempt: LastAttempt?

    public init(
        id: String,
        sourceID: UUID? = nil,
        title: String,
        remote: URL,
        mediaType: String,
        state: State = .queued,
        expectedBytes: Int64? = nil,
        downloadedBytes: Int64 = 0,
        completedAt: Date? = nil,
        verificationFailures: Int = 0,
        lastAttempt: LastAttempt? = nil
    ) {
        self.id = id
        self.sourceID = sourceID
        self.title = title
        self.remote = remote
        self.mediaType = mediaType
        self.state = state
        self.expectedBytes = expectedBytes
        self.downloadedBytes = downloadedBytes
        self.completedAt = completedAt
        self.verificationFailures = verificationFailures
        self.lastAttempt = lastAttempt
    }

    /// What the last attempt at this download did, for the row to state in the reader's own
    /// words rather than the network's.
    ///
    /// Carries a raw value for the reason ``Pause`` does: ``Persistence/DownloadStore``
    /// writes the case name down, and each platform's store is its own.
    public enum LastAttempt: String, Sendable, Equatable {
        /// Carried on from where an earlier attempt stopped.
        case resumed
        /// Started over, whether because nothing was left to carry on from or because the
        /// server would not continue what was already on disk.
        case restarted

        /// What the last attempt was, from whether there was something to try carrying on
        /// from and what actually happened to it.
        ///
        /// Lifted out of ``LibraryFeature/DownloadQueueTransfer`` so it is testable on its
        /// own: that file asks the background session for a file and cannot itself be
        /// driven by a test without a real transfer.
        ///
        /// `nil` for a first attempt — one that never asked the system to carry anything on
        /// has nothing to call either a resume or a restart.
        public static func of(hadSomethingToResume: Bool, resumed: Bool) -> LastAttempt? {
            guard hadSomethingToResume else { return nil }
            return resumed ? .resumed : .restarted
        }
    }

    /// Where a download is in its life.
    public enum State: Sendable, Equatable {
        case queued
        case running
        case paused(Pause)

        /// Retried and still failing. `offline-downloads`: after three attempts a download
        /// is "marked failed with a plain-language reason and a retry action", so both the
        /// reason and the count are part of the state rather than logged and forgotten.
        case failed(reason: String, attempts: Int)

        case finished

        /// Whether the file on disk is complete and verified.
        public var isFinished: Bool { self == .finished }

        /// Whether the app should be moving bytes for this one.
        public var isActive: Bool { self == .running || self == .queued }
    }

    /// Why a download is not running, in the reader's terms rather than the system's.
    ///
    /// Carries a raw value so ``DownloadStore`` can write the reason down: a paused record
    /// that came back queued made every "waiting for Wi-Fi" sentence unreachable in the
    /// running app. The case name is the spelling, and each platform's store is its own —
    /// Android writes its enum's `name`, which is the same three reasons in Kotlin's
    /// spelling, and neither store ever reads the other's file.
    public enum Pause: String, Sendable, Equatable {
        /// The reader asked.
        case byReader

        /// `offline-downloads`: on a metered connection with Wi-Fi-only on, downloads
        /// "pause and state that they are waiting for Wi-Fi".
        case waitingForWiFi

        /// The device is out of room. Never resolved by deleting something silently: the
        /// spec says the app "never deletes a download without asking".
        case outOfSpace
    }

    /// How far along, when the size is known.
    ///
    /// `nil` rather than zero for an unknown size, so a progress bar can show an
    /// indeterminate state instead of a bar that never moves.
    public var fraction: Double? {
        guard let expectedBytes, expectedBytes > 0 else { return nil }
        return min(1, Double(downloadedBytes) / Double(expectedBytes))
    }

    /// The record for a copy that has already finished, such as one `keptForOffline` just
    /// wrote in a single pass rather than through the download queue.
    ///
    /// Lifted here rather than built inline at the one call site that needs it today: the
    /// fields that make a record *this publication's*, from *this remote*, at *this
    /// size* — are a rule worth a name and a test of its own, not an app-layer literal
    /// nothing else can check.
    public static func finishedCopy(
        of publication: Publication,
        remote: URL,
        mediaType: String,
        bytes: Int64,
        completedAt: Date = Date()
    ) -> Download {
        Download(
            id: publication.id,
            sourceID: publication.sourceID,
            title: publication.displayTitle,
            remote: remote,
            mediaType: mediaType,
            state: .finished,
            expectedBytes: bytes,
            downloadedBytes: bytes,
            completedAt: completedAt
        )
    }
}
