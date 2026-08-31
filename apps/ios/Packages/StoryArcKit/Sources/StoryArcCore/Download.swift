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
        verificationFailures: Int = 0
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
    public enum Pause: Sendable, Equatable {
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
}
