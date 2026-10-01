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

    /// A caller suspended on one transfer, and whether the system carried it on from an
    /// earlier attempt or started it over — the `Content-Range` answer only this layer
    /// sees, since the record it belongs on lives above the session.
    private typealias Waiter = CheckedContinuation<(file: URL, resumed: Bool), any Error>

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
    private let waiting = Mutex<[String: Waiter]>([:])

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
    ///
    /// **Cancelling the caller cancels the transfer.** The download queue holds a download by
    /// cancelling the task that awaits it — that is how `offline-downloads`' *Wi-Fi only* stops
    /// a transfer already running. A bare `withCheckedThrowingContinuation` does not carry
    /// cancellation to the system, so the task ran on, the whole file arrived over the
    /// connection the reader asked the app not to use, and the row that said "waiting for
    /// Wi-Fi" was then marked finished. Every return of Wi-Fi added another copy of the same
    /// transfer, because the first one was never stopped.
    /// One transfer, carried on from `resumingWith` when the system left something to carry.
    ///
    /// `offline-downloads`' *Resuming after interruption*: an interrupted download "resumes
    /// from where it stopped if the server supports range requests, and restarts otherwise".
    /// A background `URLSession` holds the fetched bytes where this app cannot reach them, so
    /// the resume is the system's own — the token ``stop(_:named:)`` collects, handed back
    /// here. `URLSession` sends the ranged request, validates the answer against what it
    /// already has, and starts over by itself when the server will not resume.
    ///
    /// A token the system will not take is not a failure worth reporting: the download is
    /// still wanted, and starting it over is what the reader asked for either way.
    public func download(
        _ request: URLRequest,
        named: String,
        resumingWith resumeData: Data? = nil
    ) async throws -> (file: URL, resumed: Bool) {
        let task = resumeData.map(session.downloadTask(withResumeData:))
            ?? session.downloadTask(with: request)
        task.taskDescription = named
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // Displaced rather than dropped. Two transfers under one name is a queue bug
                // rather than a state to support, and leaving the first continuation unresumed
                // suspends its caller for the life of the process.
                let displaced = waiting.withLock { waiting -> Waiter? in
                    let displaced = waiting[named]
                    waiting[named] = continuation
                    return displaced
                }
                displaced?.resume(throwing: CancellationError())
                // Cancelled before the continuation was filed, so the handler below found
                // nothing to tell. Told here instead, and the task is not started.
                guard !Task.isCancelled else {
                    stop(task, named: named)
                    return
                }
                task.resume()
            }
        } onCancel: {
            stop(task, named: named)
        }
    }

    /// Stops the system's task and tells whoever is waiting, exactly once.
    ///
    /// The removal and the resume are one locked step, so a completion arriving at the same
    /// moment finds no waiter and resumes nothing.
    /// Stops a transfer, and keeps what the system will give back of it.
    ///
    /// `cancel(byProducingResumeData:)` rather than `cancel()`. The queue cancels in order to
    /// *hold* a download — for Wi-Fi, for room on the device, or because the reader asked —
    /// and a plain cancel throws the fetched bytes away, so every return of Wi-Fi started the
    /// same 400 MB comic again from nothing.
    ///
    /// The caller is told at once and the token arrives later, because those are two
    /// different moments: the system has to close the file before it can describe it. A
    /// transfer with nothing worth resuming yields no token, which is the honest answer and
    /// leaves the next attempt to start over.
    private func stop(_ task: URLSessionDownloadTask, named: String) {
        task.cancel { [weak self] data in
            guard let data, let handler = self?.resumable.withLock({ $0 }) else { return }
            handler(named, data)
        }
        waiting.withLock { $0.removeValue(forKey: named) }?.resume(throwing: CancellationError())
    }

    /// Told when a stopped transfer left something to carry on from.
    public func onResumable(_ handler: (@Sendable (String, Data) -> Void)?) {
        resumable.withLock { $0 = handler }
    }

    private let resumable = Mutex<(@Sendable (String, Data) -> Void)?>(nil)

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

    private let progress = Mutex<(@Sendable (String, Int64, Int64) -> Void)?>(nil)

    /// How often a named transfer is told apart, at most.
    ///
    /// `didWriteData` fires once per socket read, far more often than any screen needs to
    /// redraw at. `offline-downloads` wants a row to visibly move, not every packet relayed
    /// to it.
    private static let progressInterval: TimeInterval = 0.2

    /// The last moment each named transfer was told apart, so the throttle above has
    /// something to measure against.
    private let lastProgress = Mutex<[String: Date]>([:])

    /// Told how many bytes have landed for a named transfer, throttled to a few times a
    /// second.
    public func onProgress(_ handler: (@Sendable (String, Int64, Int64) -> Void)?) {
        progress.withLock { $0 = handler }
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
        // 206 is the one status a ranged request gets when the server actually continued
        // the file; `offline-downloads`' *Resuming after interruption* says it "starts over
        // otherwise", and a 200 is that — whether because nothing was asked to be resumed,
        // or because the server answered the whole resource anyway.
        let resumed = (downloadTask.response as? HTTPURLResponse)?.statusCode == 206
        resume(downloadTask, with: .success((kept, resumed)))
    }

    /// Reports how far a download has got, throttled to ``progressInterval``.
    ///
    /// `offline-downloads`' *Progress never moves during a transfer*: the queue set an
    /// expected total at enqueue and had nothing that ever advanced the other half of the
    /// fraction. This is that other half.
    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let name = downloadTask.taskDescription,
              let handler = progress.withLock({ $0 })
        else { return }
        let now = Date()
        let due = lastProgress.withLock { last -> Bool in
            if let previous = last[name], now.timeIntervalSince(previous) < Self.progressInterval {
                return false
            }
            last[name] = now
            return true
        }
        guard due else { return }
        handler(name, totalBytesWritten, totalBytesExpectedToWrite)
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        guard let error else { return }
        // The system hands back what it fetched here as well as from
        // `cancel(byProducingResumeData:)`, and this is the path a dropped connection takes —
        // the first interruption `offline-downloads` names. Read before the failure is
        // reported, because reporting it is what decides whether the download has another
        // attempt for the token to belong to.
        carryOn(from: error, of: task)
        resume(task, with: .failure(error))
    }

    /// Hands on what the system left of a transfer that ended in an error.
    ///
    /// A transfer with nothing worth resuming carries no token, and a connection that dropped
    /// before anything arrived is one of those. Nothing is reported in that case: the download
    /// is still wanted and starting it over is what happens anyway.
    private func carryOn(from error: any Error, of task: URLSessionTask) {
        guard let name = task.taskDescription,
              let data = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data,
              let handler = resumable.withLock({ $0 })
        else { return }
        handler(name, data)
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

    /// The same redirect rule the ordinary client follows.
    ///
    /// A download is the one request in the app that carries a credential to a URL the
    /// catalogue chose, and it runs unattended. A 302 out of the source's origin drops the
    /// header here exactly as it does there.
    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        OpdsRedirect.following(request, from: task.originalRequest)
    }

    private func resume(_ task: URLSessionTask, with outcome: Result<(file: URL, resumed: Bool), any Error>) {
        guard let name = task.taskDescription else { return }
        lastProgress.withLock { $0.removeValue(forKey: name) }
        let continuation = waiting.withLock { $0.removeValue(forKey: name) }
        if let continuation {
            continuation.resume(with: outcome)
            return
        }
        // Nobody is waiting: this is a transfer that outlived the process that asked for it.
        guard case let .success((file, _)) = outcome else { return }
        let adopt = orphan.withLock { $0 }
        if let adopt {
            adopt(name, file)
        } else {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
