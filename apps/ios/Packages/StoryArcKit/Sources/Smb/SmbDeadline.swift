public import Foundation

/// Runs an operation, but fails with ``SmbError/hostUnreachable`` rather than waiting past a
/// deadline — the one thing a plain `await` on a socket that never answers cannot do on its
/// own.
///
/// `network-share`'s *Connection drops while reading*: a silent drop used to wait forever,
/// because `NWConnection.receive` has no timeout of its own and `SmbSource` set none either —
/// the 2 s notice and the 60 s offer both depend on `SmbReachability.noteFailure()` running,
/// and it never ran. A type of its own, beside `SmbSource` rather than nested in it, so a
/// test can drive the race directly instead of needing a share that hangs on cue — and its
/// own file, at the 400-line cap's own insistence once `SmbClient.swift` reached it.
enum SmbDeadline {
    /// Races `operation` against `Task.sleep(for: duration)` and returns whichever finishes
    /// first, cancelling the other. `operation` losing the race throws
    /// ``SmbError/hostUnreachable``; `operation` finishing or throwing first is returned or
    /// rethrown exactly as it happened; the deadline itself is never a false success.
    static func run<T: Sendable>(
        within duration: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: duration)
                throw SmbError.hostUnreachable
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw SmbError.hostUnreachable }
            return result
        }
    }
}
