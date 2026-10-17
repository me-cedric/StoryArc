import Foundation

/// Waits for work or for a deadline, whichever comes first, and never longer.
///
/// A task group cannot do this: it waits for every child before it returns, and awaiting an
/// unstructured task's value does not answer cancellation, so a slow child keeps the group
/// open past the deadline. A continuation resumed once by whichever finishes first returns at
/// the deadline and leaves the slow work to end on its own. Measured by `SyncTests`.
enum Deadline {
    /// True when `work` finished before `limit`.
    @MainActor
    static func race(_ work: Task<Void, Never>, limit: Duration) async -> Bool {
        await withCheckedContinuation { continuation in
            let once = Once(continuation)
            Task { @MainActor in
                await work.value
                once.resume(true)
            }
            Task { @MainActor in
                try? await Task.sleep(for: limit)
                once.resume(false)
            }
        }
    }

    @MainActor
    private final class Once {
        private var continuation: CheckedContinuation<Bool, Never>?

        init(_ continuation: CheckedContinuation<Bool, Never>) { self.continuation = continuation }

        func resume(_ value: Bool) {
            continuation?.resume(returning: value)
            continuation = nil
        }
    }
}
