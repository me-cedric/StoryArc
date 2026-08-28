public import Foundation

internal import Synchronization

/// Whether reads from shares are getting through.
///
/// `network-share` asks for an indicator "only if a page is actually blocked on the network
/// for more than 2 seconds", and for an offer to download after 60 seconds of failure. Both
/// are questions about time, so what is published is *when* trouble started rather than a
/// boolean — a screen can then decide its own thresholds without this having to know them.
///
/// One object for the whole app rather than one per source: a reader turning pages holds one
/// archive, and two indicators for one dropped Wi-Fi would be one too many.
public enum SmbReachability {
    private static let state = Mutex<Date?>(nil)

    /// When reads started failing, or nil while they are getting through.
    public static var blockedSince: Date? {
        state.withLock { $0 }
    }

    /// A read failed. The first failure is the one whose time is kept.
    public static func noteFailure(at moment: Date = Date()) {
        state.withLock { if $0 == nil { $0 = moment } }
    }

    /// A read got through. Whatever was wrong is over.
    public static func noteSuccess() {
        state.withLock { $0 = nil }
    }

    /// Forgets the current trouble, for a reader who dismissed the notice.
    public static func clear() {
        state.withLock { $0 = nil }
    }
}
