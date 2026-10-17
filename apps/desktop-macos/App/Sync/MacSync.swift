import Foundation
import Persistence
import StoryArcCore

/// Library sync on a Mac: at start and at quit, the moments a phone calls foreground and
/// background (`desktop-experience`, *Sync when the app runs*).
///
/// The runner, the place and the merge are StoryArcKit's (`LibrarySyncRunner`,
/// `LibraryTransfer`); this decides when. At start the sync is a task of its own, so the
/// window never waits, and Home holds Keep reading back until the merge lands or five seconds
/// pass, whichever is first, so a shelf is not drawn and then redrawn. At quit it writes once
/// more only when a position changed since the last sync, and gives up after five seconds:
/// the app quits regardless. An unreachable place leaves the runner's grey status and
/// nothing else. No background process is left: nothing runs after the quit.
@MainActor
@Observable
final class MacSync {
    enum QuitOutcome: Equatable {
        case off
        case nothingNew
        case synced
        case gaveUp
    }

    static let quitDeadline: Duration = .seconds(5)
    static let startPatience: Duration = .seconds(5)

    let runner: LibrarySyncRunner?
    /// Whether Home may draw Keep reading: the start's merge landed, or it is taking too long.
    private(set) var hasSettledStart = false

    @ObservationIgnored private let latestChange: () async -> Date?
    @ObservationIgnored private var lastSync: Date?

    /// - Parameter latestChange: when a reading position last changed, from the progress store.
    init(runner: LibrarySyncRunner?, latestChange: @escaping () async -> Date?) {
        self.runner = runner
        self.latestChange = latestChange
    }

    /// The start's sync, beside the window. `reload` runs once the merge has written the stores.
    func start(reload: @escaping @MainActor () async -> Void) {
        guard let runner, runner.choice != nil else {
            hasSettledStart = true
            return
        }
        let began = Date()
        Task {
            await runner.run(.foreground)
            lastSync = began
            await reload()
            hasSettledStart = true
        }
        Task {
            try? await Task.sleep(for: Self.startPatience)
            hasSettledStart = true
        }
    }

    /// The quit's sync: once more if a position changed, and never longer than five seconds.
    func atQuit() async -> QuitOutcome {
        guard let runner, runner.choice != nil else { return .off }
        guard let changed = await latestChange(), lastSync.map({ changed > $0 }) ?? true else {
            return .nothingNew
        }
        let work = Task { @MainActor in _ = await runner.run(.leftPublication) }
        let inTime = await Deadline.race(work, limit: Self.quitDeadline)
        if inTime { lastSync = Date() }
        return inTime ? .synced : .gaveUp
    }
}
