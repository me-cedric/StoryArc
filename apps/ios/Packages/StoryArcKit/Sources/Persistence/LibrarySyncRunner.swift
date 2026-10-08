public import Foundation
public import Observation
public import StoryArcCore

/// When a sync runs, and what the reader sees of it.
///
/// `library-sync` tasks 2.4, 4.1, 4.2 and 4.3. Each trigger calls ``run(_:)``. While no place is
/// chosen, ``run(_:)`` does nothing at all. A trigger that comes while a sync runs makes that sync
/// run once more when it ends, so a position saved during a sync is not left out. Any failure of
/// the place is ``Status/unreachable`` and queues one retry: the next trigger runs even inside the
/// foreground throttle. Android's `LibrarySyncRunner` is the same runner.
///
/// On the main actor, because Settings draws ``status`` and the app's triggers arrive there. The
/// sync itself runs off it, in ``LibraryTransfer``.
@MainActor
@Observable
public final class LibrarySyncRunner {
    public enum Trigger: Sendable, CaseIterable {
        /// The reader chose a place.
        case chosen
        /// The app came to the foreground. At most one run per ``LibrarySyncRunner/throttle``.
        case foreground
        /// The reader left a publication the document carries.
        case leftPublication
        /// The system's background refresh.
        case background
    }

    /// What the sync is doing, for the Settings line. An unreachable place is grey, never red.
    public enum Status: Sendable, Equatable {
        /// No place is chosen. Nothing is written, read or looked for.
        case off
        /// A place is chosen and no sync ran yet in this launch.
        case idle
        case syncing
        case synced(Date)
        /// The place did not answer. The library keeps working, and the next trigger tries again.
        case unreachable
        /// The document in the place cannot be read, by name. Nothing was written over it.
        case refused(LibraryDocumentFailure)
    }

    public static let throttle: TimeInterval = 30

    public private(set) var status: Status

    /// Runs after each sync that wrote the stores, so the app reloads what it holds in memory.
    @ObservationIgnored public var onSynced: (@MainActor () -> Void)?

    @ObservationIgnored private let places: SyncPlaceStore
    @ObservationIgnored private let placeFor: @MainActor (SyncPlaceChoice) async -> (any SyncPlace)?
    @ObservationIgnored private let sync: @Sendable (any SyncPlace) async throws -> LibrarySyncOutcome
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var again = false
    @ObservationIgnored private var lastStart: Date?
    @ObservationIgnored private var retryPending = false

    /// - Parameters:
    ///   - placeFor: the place for a choice, or nil when it cannot be built (a removed share).
    ///   - sync: one read, merge and write with that place: `LibraryTransfer.sync`.
    public init(
        places: SyncPlaceStore,
        placeFor: @escaping @MainActor (SyncPlaceChoice) async -> (any SyncPlace)?,
        sync: @escaping @Sendable (any SyncPlace) async throws -> LibrarySyncOutcome,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.places = places
        self.placeFor = placeFor
        self.sync = sync
        self.now = now
        status = places.choice() == nil ? .off : .idle
    }

    /// The chosen place, or nil while sync is off.
    public var choice: SyncPlaceChoice? { places.choice() }

    /// Chooses a share the reader already added.
    public func chooseShare(_ sourceID: UUID) {
        places.chooseShare(sourceID)
        chose(isOn: true)
    }

    /// Chooses a folder the system picker returned. The caller holds its security scope open.
    public func chooseFolder(_ url: URL) throws {
        try places.chooseFolder(url)
        chose(isOn: true)
    }

    public func turnOff() {
        places.turnOff()
        chose(isOn: false)
    }

    /// One sync, unless sync is off, the foreground throttle skips it, or a sync is running.
    ///
    /// - Returns: true when this call ran a sync.
    @discardableResult
    public func run(_ trigger: Trigger) async -> Bool {
        guard places.choice() != nil else {
            status = .off
            return false
        }
        if trigger == .foreground, !retryPending, let lastStart, now().timeIntervalSince(lastStart) < Self.throttle {
            return false
        }
        guard !isRunning else {
            again = true
            return false
        }
        isRunning = true
        defer { isRunning = false }
        repeat {
            again = false
            await once()
        } while again
        return true
    }

    /// The reader left a publication: its position goes to the place at once.
    ///
    /// A Kavita publication's position goes to Kavita, not into the document (task 3.7), so it
    /// starts no sync.
    @discardableResult
    public func leftPublication(ownedByKavita: Bool) async -> Bool {
        ownedByKavita ? false : await run(.leftPublication)
    }

    private func chose(isOn: Bool) {
        retryPending = false
        lastStart = nil
        status = isOn ? .idle : .off
    }

    private func once() async {
        guard let choice = places.choice() else {
            status = .off
            return
        }
        lastStart = now()
        let before = status
        status = .syncing
        let outcome = await attempt(choice)
        retryPending = outcome == nil || outcome == .busy
        switch outcome {
        case nil:
            status = .unreachable
        case .synced:
            status = .synced(now())
            onSynced?()
        case let .refused(reason):
            status = .refused(reason)
        case .busy:
            // Another device wrote under every attempt. The place answered, so it is not
            // unreachable; the next trigger tries again.
            status = before == .syncing ? .idle : before
        }
    }

    /// The outcome, or nil when the place could not be built or did not answer.
    private func attempt(_ choice: SyncPlaceChoice) async -> LibrarySyncOutcome? {
        guard let place = await placeFor(choice) else { return nil }
        return try? await sync(place)
    }
}
