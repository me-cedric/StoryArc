public import Foundation

/// How fast the words come, without changing what they sound like.
///
/// **The range is a product decision**, recorded as one in `design.md`: 0.5× to 3×, the
/// range spoken-word listeners actually use. Neither Apple nor Material publishes guidance
/// on it, so nothing here cites one. `audio-playback` states the floor as a requirement —
/// "at least the range from half speed to triple speed is offered".
///
/// A value that clamps rather than an enum of stops: a remembered speed read back from a
/// store, or one arriving from a slider, has to land somewhere valid without a caller
/// remembering to check.
public struct PlaybackSpeed: Sendable, Equatable, Comparable, Codable {
    /// The bounds as bare numbers, and they have to be.
    ///
    /// ``init(_:)`` clamps against these, so reading them from `slowest.rate` and
    /// `fastest.rate` instead made the initialiser wait on the one-time initialisation of a
    /// value the initialiser was building — a deadlock inside `dispatch_once`, on the first
    /// `PlayerCentre()` anything made. It crashed the first run of the first test rather
    /// than shipping, which is the argument for writing the test before the type.
    public static let slowestRate = 0.5
    public static let fastestRate = 3.0

    public static let slowest = PlaybackSpeed(slowestRate)
    public static let normal = PlaybackSpeed(1)
    public static let fastest = PlaybackSpeed(fastestRate)

    public let rate: Double

    public init(_ rate: Double) {
        self.rate = min(Self.fastestRate, max(Self.slowestRate, rate))
    }

    public static func < (lhs: PlaybackSpeed, rhs: PlaybackSpeed) -> Bool { lhs.rate < rhs.rate }

    /// The stops a picker offers, which is not the same as the range it permits.
    public static let stops: [PlaybackSpeed] = [
        PlaybackSpeed(0.5), PlaybackSpeed(0.75), PlaybackSpeed(1), PlaybackSpeed(1.25),
        PlaybackSpeed(1.5), PlaybackSpeed(1.75), PlaybackSpeed(2), PlaybackSpeed(2.5),
        PlaybackSpeed(3),
    ]
}

/// Which way a skip goes.
public enum SkipDirection: Sendable, Equatable {
    case back
    case forward
}

/// What one press of a skip control moves.
///
/// The two sources genuinely differ, and the honest answer is to say which rather than to
/// pretend. `audio-playback` requires the interval to be "stated on the control itself",
/// and a synthesised voice has no seconds to state — `ebook-reader` asks its media controls
/// for "sentence skip" by name. Same two buttons in the same two places; different words on
/// them.
public enum SkipUnit: Sendable, Equatable {
    /// Seconds, by the interval the listener configured.
    case time
    /// One sentence, which is all a synthesised voice can offer.
    case sentence
}

/// How far a skip goes.
///
/// **The defaults are a product decision**, recorded as one in `design.md`: 15 seconds back
/// and 30 seconds forward. Back is shorter because the reason to skip back is "I missed
/// that sentence" and the reason to skip forward is "I know this part". media3's own
/// defaults — 5 s and 15 s — are wrong for spoken word in the other direction, and no
/// platform guidance covers it either way.
///
/// `audio-playback` requires the interval to be one "the listener can configure", which is
/// why this is a stored value rather than two constants.
public struct SkipIntervals: Sendable, Equatable, Codable {
    public var back: TimeInterval
    public var forward: TimeInterval

    public init(back: TimeInterval = 15, forward: TimeInterval = 30) {
        self.back = back
        self.forward = forward
    }

    public static let `default` = SkipIntervals()

    /// What the picker offers, in seconds.
    ///
    /// **The same four Android offers**, and that is the point of stating them here rather than
    /// in the view: a listener who sets ten seconds on a phone and finds no ten on a tablet is a
    /// listener the set has drifted under. A product decision like the defaults above, with no
    /// platform guidance behind it either way.
    public static let offered: [TimeInterval] = [5, 10, 15, 30]

    public func interval(_ direction: SkipDirection) -> TimeInterval {
        switch direction {
        case .back: back
        case .forward: forward
        }
    }
}
