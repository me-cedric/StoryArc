public import Foundation

internal import Synchronization

/// Downloads that keep going when the app does not.
///
/// `offline-downloads`: backgrounded downloads "continue under the platform's background
/// transfer mechanism as far as the platform allows". On iOS that mechanism is a background
/// `URLSession`, which hands the transfer to the system: it survives the app being
/// suspended, and hands the finished file back on the next launch if it has to.
///
/// A background session cannot use `data(for:)` — only download and upload tasks — so this
/// is a download task with the completion delivered through the delegate. The pinning
/// delegate is the same one the ordinary client uses; a download that skipped the pin check
/// would be the one request in the app that did.
public final class BackgroundTransfers: NSObject, @unchecked Sendable {
    /// The one the system remembers between launches. It has to be stable.
    public static let identifier = "app.storyarc.downloads"

    private static let instance = Mutex<BackgroundTransfers?>(nil)

    /// The one background session for the whole app.
    ///
    /// Not a convenience: two `URLSession`s sharing a background identifier is a programmer
    /// error, and the download queue is built per catalogue screen. One session, however
    /// many queues.
    public static func shared(pins: CertificatePins = CertificatePins()) -> BackgroundTransfers {
        instance.withLock { existing in
            if let existing { return existing }
            let made = BackgroundTransfers(pins: pins)
            existing = made
            return made
        }
    }

    private let trust: OpdsTrustDelegate
    /// Keyed by the caller's own name for the download, not by `taskIdentifier`.
    ///
    /// The identifier is the session's, and the session renumbers when it reconnects to the
    /// transfer daemon. A continuation filed under the old number is one nothing can find.
    private let waiting = Mutex<[String: CheckedContinuation<URL, any Error>]>([:])
    private let made = Mutex<URLSession?>(nil)

    private let finished = Mutex<(@Sendable () -> Void)?>(nil)
    private let orphan = Mutex<(@Sendable (String, URL) -> Void)?>(nil)

    /// What to call when the system has delivered everything it was holding.
    ///
    /// The app hands this over so the system knows it has finished reacting; without it,
    /// iOS counts the wake-up against the app.
    public func onFinishedEvents(_ handler: (@Sendable () -> Void)?) {
        finished.withLock { $0 = handler }
    }

    /// Built on first use, because the delegate is `self` and `self` does not exist until
    /// `super.init` has run.
    private var session: URLSession {
        made.withLock { existing in
            if let existing { return existing }
            let configuration = URLSessionConfiguration.background(withIdentifier: Self.identifier)
            // The system decides when, which is the point. `offline-downloads` also forbids
            // *claiming* a download will finish while suspended, and this is the honest
            // arrangement: it continues if the system lets it, and resumes if it does not.
            configuration.isDiscretionary = false
            configuration.sessionSendsLaunchEvents = true
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            existing = session
            return session
        }
    }

    private init(pins: CertificatePins) {
        trust = OpdsTrustDelegate(pins: pins)
        super.init()
    }

    /// Fetches one file, returning where the system put it.
    ///
    /// `named` is written onto the task, which the system stores with it. That is what makes
    /// a transfer identifiable after the app has been killed and relaunched: the continuation
    /// waiting here does not survive that, and the task does.
    public func download(_ request: URLRequest, named: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.downloadTask(with: request)
            task.taskDescription = named
            waiting.withLock { $0[named] = continuation }
            task.resume()
        }
    }

    /// The names of the transfers the system is still carrying.
    ///
    /// A caller that believes a download is running, and does not find it here, is waiting
    /// for something nobody is doing.
    public func outstanding() async -> Set<String> {
        // Only the live ones. A task the session still lists but has finished is a transfer
        // whose completion never reached this process, and counting it as in flight is what
        // leaves a download saying "fetching" for ever.
        let live = await session.allTasks.filter { $0.state == .running || $0.state == .suspended }
        return Set(live.compactMap(\.taskDescription))
    }

    /// What to do with a finished transfer that nothing is waiting for.
    ///
    /// After a relaunch there is never a waiter: the continuation died with the process
    /// while the transfer went on. Without this the bytes the system worked for are thrown
    /// away and fetched again.
    public func onOrphan(_ handler: (@Sendable (String, URL) -> Void)?) {
        orphan.withLock { $0 = handler }
    }
}

extension BackgroundTransfers: URLSessionDownloadDelegate {
    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Moved here and now: the system deletes the temporary file the moment this method
        // returns, so a continuation resumed with the original URL would be handed a path
        // to nothing.
        let kept = FileManager.default.temporaryDirectory
            .appending(path: "storyarc-\(downloadTask.taskIdentifier)")
        try? FileManager.default.removeItem(at: kept)
        do {
            try FileManager.default.moveItem(at: location, to: kept)
        } catch {
            resume(downloadTask, with: .failure(error))
            return
        }
        resume(downloadTask, with: .success(kept))
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        guard let error else { return }
        resume(task, with: .failure(error))
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        finished.withLock { $0 }?()
    }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        // The ordinary client's own delegate, not a second opinion: a download that skipped
        // the pin check would be the one request in the app that did.
        await trust.urlSession(session, didReceive: challenge)
    }

    private func resume(_ task: URLSessionTask, with outcome: Result<URL, any Error>) {
        guard let name = task.taskDescription else { return }
        let continuation = waiting.withLock { $0.removeValue(forKey: name) }
        if let continuation {
            continuation.resume(with: outcome)
            return
        }
        // Nobody is waiting: this is a transfer that outlived the process that asked for it.
        guard case let .success(file) = outcome else { return }
        let adopt = orphan.withLock { $0 }
        if let adopt {
            adopt(name, file)
        } else {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
