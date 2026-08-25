public import Foundation

/// Which way a continuous scroll runs.
///
/// Separate from ``PageTransition`` because `page-transitions` treats it that way:
/// the picker offers four modes, and "the axis is separately overridable".
public enum ScrollAxis: String, Sendable, Codable, CaseIterable {
    case vertical
    case horizontal

    /// The axis a publication implies.
    ///
    /// `page-transitions`: "the axis follows the publication's reading direction —
    /// vertical for webtoons and reflowable text, horizontal where the publication
    /// declares it". A webtoon is one tall strip cut into files; scrolling it
    /// sideways is not a preference anyone holds.
    ///
    /// - Parameter isTall: whether the pages are materially taller than they are
    ///   wide, which is what `comic-reader` uses to recognise a webtoon that does not
    ///   say it is one.
    public static func implied(
        isReflowable: Bool,
        isTall: Bool,
        declaresHorizontal: Bool
    ) -> ScrollAxis {
        if isReflowable || isTall { return .vertical }
        return declaresHorizontal ? .horizontal : .vertical
    }

    /// How much taller than wide a page has to be to read as a strip.
    ///
    /// A comic page is around 0.65 wide-to-tall and a webtoon panel strip is many
    /// times its width. Two is far above the first and far below the second, so it
    /// separates them without needing to be tuned.
    public static let tallnessThreshold = 2.0
}

/// Why a transition is offered but cannot run.
public enum TransitionUnavailability: String, Sendable, Equatable {
    /// The system's Reduce Motion setting is on.
    ///
    /// `page-transitions`: Curl and Slide are replaced by Fast fade, and "the picker
    /// still lists them, marked unavailable, with the reason named — a control that
    /// vanishes teaches the user nothing".
    case reduceMotion
}

/// What the transition picker should show, and what actually runs.
///
/// Two distinct treatments, because the spec asks for two:
///
/// - Reduce Motion leaves Curl and Slide **listed and marked**, because the reader
///   turned that setting on and can turn it off.
/// - A device that cannot render the curl leaves Curl **absent**, with the reason
///   stated once — there is nothing the reader can do about it, and a permanently
///   dead row is furniture.
///
/// In both cases the stored choice is untouched. `page-transitions` requires that a
/// reader who set Curl on a capable device "reads with Slide without their stored
/// preference being overwritten".
public struct TransitionChoices: Sendable, Equatable {
    /// What the reader chose. What stays stored.
    public let chosen: PageTransition

    /// What runs now.
    public let effective: PageTransition

    /// The rows to draw, in order.
    public let offered: [PageTransition]

    /// Of those rows, the ones that cannot run, and why.
    public let unavailable: [PageTransition: TransitionUnavailability]

    /// Whether the curl is missing because this device cannot honour it, which is the
    /// one case that needs a sentence outside the list.
    public let curlIsAbsent: Bool

    /// The axis the publication implies, which is the scroll row shown as suggested.
    public let impliedAxis: ScrollAxis

    /// - Parameters:
    ///   - axis: the axis the publication implies. Both scroll rows are offered
    ///     regardless — `page-transitions` requires the axis to be "separately
    ///     overridable", and two rows are that override with no second control to
    ///     find. ponytail: two rows, not a mode plus an axis picker; split them if a
    ///     third axis ever exists.
    ///   - canCurl: whether this device can render the curl at the display's refresh
    ///     rate. `page-transitions`: "the app never ships a curl that stutters in
    ///     preference to a slide that does not".
    public init(
        chosen: PageTransition,
        axis: ScrollAxis,
        reduceMotion: Bool,
        canCurl: Bool
    ) {
        self.chosen = chosen
        self.curlIsAbsent = !canCurl
        self.impliedAxis = axis

        var offered: [PageTransition] = []
        if canCurl { offered.append(.pageCurl) }
        offered.append(.slide)
        offered.append(.fastFade)
        // The implied axis first, so the row a reader most likely wants is the one
        // nearest the modes above it.
        offered.append(.scroll(axis))
        offered.append(.scroll(axis == .vertical ? .horizontal : .vertical))
        self.offered = offered

        var unavailable: [PageTransition: TransitionUnavailability] = [:]
        if reduceMotion {
            for mode in offered where mode.isAnimatedTransition {
                unavailable[mode] = .reduceMotion
            }
        }
        self.unavailable = unavailable

        // Falling back rather than rewriting. Two reasons a choice may not run, and
        // both are conditions of the moment: the setting can be turned off, and the
        // next device may be able to curl.
        var effective = chosen
        if effective == .pageCurl, !canCurl { effective = .slide }
        effective = effective.honoring(reduceMotion: reduceMotion)
        self.effective = effective
    }

    /// Whether a row can be picked.
    public func isAvailable(_ mode: PageTransition) -> Bool { unavailable[mode] == nil }
}

extension PageTransition {
    /// Whether this is the continuous mode, in either axis.
    public var isScroll: Bool { self == .verticalScroll || self == .horizontalScroll }

    /// The axis this mode scrolls along, or `nil` for the paged modes.
    public var scrollAxis: ScrollAxis? {
        switch self {
        case .verticalScroll: .vertical
        case .horizontalScroll: .horizontal
        case .pageCurl, .slide, .fastFade: nil
        }
    }

    /// The continuous mode along one axis.
    public static func scroll(_ axis: ScrollAxis) -> PageTransition {
        axis == .vertical ? .verticalScroll : .horizontalScroll
    }
}
