internal import Synchronization

/// Runs an operation, but fails with ``SmbError/hostUnreachable`` rather than waiting past a
/// deadline — the one thing a plain `await` on a socket that never answers cannot do on its
/// own.
///
/// `network-share`'s *Connection drops while reading*: a silent drop used to wait forever,
/// because `NWConnection.receive` has no timeout of its own and `SmbSource` set none either.
/// A type of its own, so a test can drive the race directly instead of needing a share that
/// hangs on cue.
///
/// **Not a task group.** A group waits for every child before it returns, and SMBClient's
/// `Connection.send` waits in a continuation that ignores cancellation — so a group that
/// cancelled its losing read still waited as long as the silent connection did, which is
/// for ever. The operation runs in a task of its own instead, and the caller is answered by
/// whichever of the two finishes first. The losing operation is told to cancel and left to
/// end on its own; `SmbSource` disconnects the session under it, which is what ends it.
enum SmbDeadline {
    static func run<T: Sendable>(
        within duration: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let race = Race<T>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                race.hold(continuation)
                let work = Task {
                    do {
                        race.settle(.success(try await operation()))
                    } catch {
                        race.settle(.failure(error))
                    }
                }
                let deadline = Task {
                    guard (try? await Task.sleep(for: duration)) != nil else { return }
                    race.settle(.failure(SmbError.hostUnreachable))
                }
                race.track([work, deadline])
            }
        } onCancel: {
            race.settle(.failure(CancellationError()))
        }
    }
}

/// The first answer of several, delivered once.
///
/// Whichever of the operation, the deadline and the caller's own cancellation settles first
/// resumes the caller, and the rest are cancelled. A settle that arrives before the caller
/// is held is kept and delivered the moment it is.
private final class Race<T: Sendable>: Sendable {
    private struct State {
        var continuation: CheckedContinuation<T, any Error>?
        var outcome: Result<T, any Error>?
        var tasks: [Task<Void, Never>] = []
    }

    private let state = Mutex(State())

    func hold(_ continuation: CheckedContinuation<T, any Error>) {
        let early = state.withLock { state -> Result<T, any Error>? in
            if state.outcome == nil { state.continuation = continuation }
            return state.outcome
        }
        if let early { continuation.resume(with: early) }
    }

    func track(_ tasks: [Task<Void, Never>]) {
        let isSettled = state.withLock { state -> Bool in
            if state.outcome == nil { state.tasks += tasks }
            return state.outcome != nil
        }
        if isSettled { tasks.forEach { $0.cancel() } }
    }

    func settle(_ result: Result<T, any Error>) {
        let taken = state.withLock { state -> (CheckedContinuation<T, any Error>?, [Task<Void, Never>])? in
            guard state.outcome == nil else { return nil }
            state.outcome = result
            let taken = (state.continuation, state.tasks)
            state.continuation = nil
            state.tasks = []
            return taken
        }
        guard let (continuation, tasks) = taken else { return }
        tasks.forEach { $0.cancel() }
        continuation?.resume(with: result)
    }
}
