public import Foundation

/// A source that an open reader found unreachable, told to the library.
///
/// `network-share`'s *Network changes*: when the new path cannot reach the share, the app
/// "marks the source `unreachable` rather than retrying indefinitely". The reader is the one
/// place that finds this out, and the library is the one place that holds the state. Here,
/// because both feature modules depend on this one and not on each other. Android's
/// `SourceReachabilityEvents` carries the same event.
public enum SourceReachabilityEvents {
    public static let unreachable = Notification.Name("StoryArc.SourceReachabilityEvents.unreachable")

    /// Tells the library that the path no longer reaches this source.
    public static func reportUnreachable(_ sourceID: UUID) {
        NotificationCenter.default.post(name: unreachable, object: nil, userInfo: [key: sourceID])
    }

    /// The source that a report names, or nil for any other notification.
    public static func sourceID(in notification: Notification) -> UUID? {
        notification.userInfo?[key] as? UUID
    }

    private static let key = "sourceID"
}

/// An error that says whether the source is gone, as opposed to refused or damaged.
public protocol SourceReachabilityError: Error {
    var meansUnreachable: Bool { get }
}
