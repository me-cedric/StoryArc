internal import Foundation
internal import StoryArcCore

/// A reader's "this share is gone", applied to the registry.
///
/// `network-share`'s *Network changes*, second clause. Beside ``LibraryModel`` rather than
/// in it, because that file is at the length the linter allows. Android's
/// `watchSourceReachability` is the same watch.
extension LibraryModel {
    /// Starts the watch. Called once, from ``restoreFolders()``.
    func watchSourceReachability() {
        _ = NotificationCenter.default.addObserver(
            forName: SourceReachabilityEvents.unreachable,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let id = SourceReachabilityEvents.sourceID(in: notification) else { return }
            MainActor.assumeIsolated { self?.noteUnreachable(id) }
        }
    }

    /// Marks the source unreachable. The reader asks again every few seconds while the
    /// share is away, so a source that is already unreachable keeps the moment it went.
    func noteUnreachable(_ id: UUID, at moment: Date = .now) {
        guard let source = registry[id] else { return }
        if case .unreachable = source.state { return }
        registry = registry.marking(id, as: .unreachable(since: moment), at: moment)
    }
}
