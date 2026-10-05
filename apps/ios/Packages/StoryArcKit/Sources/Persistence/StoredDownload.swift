internal import Foundation

internal import StoryArcCore

/// What ``DownloadStore`` actually writes for one ``Download``.
///
/// Split out of `DownloadStore.swift`, which reached the 400-line cap this project
/// enforces — the seam was already there, since this type only ever appears at the bottom
/// of that file's `library()` and `save(_:)`.
///
/// A separate shape rather than making ``Download`` `Codable`, for the same reason
/// `StoredRegistry` exists: the durable fields and the runtime ones are different sets. A
/// download that was *running* when the app died is queued when it comes back, because
/// "running" describes a transfer that is no longer happening.
struct StoredDownload: Codable {
    let id: String
    let sourceID: UUID?
    let title: String
    let remote: URL
    let mediaType: String
    let expectedBytes: Int64?
    let downloadedBytes: Int64
    let completedAt: Date?
    let isFinished: Bool
    let failure: String?
    let attempts: Int

    /// `offline-downloads` allows a corrupt arrival exactly one re-fetch, so the count has
    /// to outlive the process that made it — otherwise a download that was killed between
    /// its two chances comes back with both of them.
    ///
    /// Optional on the way in, because a record written by a build before this field
    /// existed has none, and `ignoreUnknownKeys` is not the same as a default.
    let verificationFailures: Int?

    /// Why the download stopped, when it stopped for a reason the reader can be told.
    ///
    /// `offline-downloads` requires a held queue to say what it is waiting for, and the
    /// settings screen asks the *records* rather than a live queue. Without this the reason
    /// died with the process: every paused row came back queued, so the screen could never
    /// draw the sentence the spec asks for.
    ///
    /// Optional for ``verificationFailures``' reason: a record written before this field
    /// existed has none, and it comes back queued.
    let pause: String?

    /// `offline-downloads`' *Resuming after interruption*: whether the transfer that
    /// produced what is on disk carried on or started over. Optional for the same reason
    /// ``pause`` is: a record written before this field existed has none, which is also the
    /// honest answer for a download that has never been interrupted.
    let lastAttempt: String?

    init(_ download: Download) {
        id = download.id
        sourceID = download.sourceID
        title = download.title
        remote = download.remote
        mediaType = download.mediaType
        expectedBytes = download.expectedBytes
        downloadedBytes = download.downloadedBytes
        completedAt = download.completedAt
        verificationFailures = download.verificationFailures
        isFinished = download.state.isFinished
        if case let .paused(reason) = download.state {
            pause = reason.rawValue
        } else {
            pause = nil
        }
        lastAttempt = download.lastAttempt?.rawValue
        if case let .failed(reason, count) = download.state {
            failure = reason
            attempts = count
        } else {
            failure = nil
            attempts = 0
        }
    }

    var download: Download {
        Download(
            id: id,
            sourceID: sourceID,
            title: title,
            remote: remote,
            mediaType: mediaType,
            state: state,
            expectedBytes: expectedBytes,
            downloadedBytes: downloadedBytes,
            completedAt: completedAt,
            verificationFailures: verificationFailures ?? 0,
            lastAttempt: lastAttempt.flatMap(Download.LastAttempt.init(rawValue:))
        )
    }

    private var state: Download.State {
        if isFinished { return .finished }
        // Normalised on the way in, which is where `localization` 15.9's migration lives: a
        // record written by an older build holds a finished English sentence, and
        // `DownloadFailure` reads anything it does not recognise as `unknown`. The row then
        // says that the download failed, in the reader's own language, rather than nothing.
        if let failure { return .failed(reason: DownloadFailure(stored: failure).stored, attempts: attempts) }
        // A spelling this build does not know is not a reason to lose the download. Queued
        // is the honest fallback: the queue asks the connection and the volume on its next
        // pump and writes whichever reason is true now.
        if let pause, let reason = Download.Pause(rawValue: pause) { return .paused(reason) }
        return .queued
    }
}
