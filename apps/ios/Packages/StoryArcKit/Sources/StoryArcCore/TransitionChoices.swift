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

    /// The publication's text reflows, and this mode needs a picture of a page.
    ///
    /// `page-transitions` states the cause itself: "the deforming surface has to be a
    /// texture, so each page must be rastered". Until that exists, Curl and Fast fade
    /// cannot run over reflowable text — and the spec's "a mode is unavailable for the
    /// content" scenario says to *say so* rather than drop the row.
    ///
    /// A comic pays none of this, which is why the same two modes work there: the page
    /// is already a decoded image.
    case reflowableText
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
    ///   - isReflowable: whether the text reflows. A reflowable page is live web
    ///     content, so the modes that deform a picture of a page cannot run over it
    ///     yet — listed with the reason rather than dropped, and only one scroll row,
    ///     because text scrolls the way it is read.
    public init(
        chosen: PageTransition,
        axis: ScrollAxis,
        reduceMotion: Bool,
        canCurl: Bool,
        isReflowable: Bool = false
    ) {
        self.chosen = chosen
        self.curlIsAbsent = !canCurl
        self.impliedAxis = axis

        var offered: [PageTransition] = []
        if canCurl { offered.append(.pageCurl) }
        offered.append(.slide)
        offered.append(.fastFade)
        if isReflowable {
            // One row, and no axis choice: reflowing text scrolls the way it is read,
            // and a horizontal river of prose is not a preference anyone holds.
            offered.append(.verticalScroll)
        } else {
            // The implied axis first, so the row a reader most likely wants is the one
            // nearest the modes above it.
            offered.append(.scroll(axis))
            offered.append(.scroll(axis == .vertical ? .horizontal : .vertical))
        }
        self.offered = offered

        var unavailable: [PageTransition: TransitionUnavailability] = [:]
        if isReflowable {
            for mode in offered where mode.needsARasteredPage {
                unavailable[mode] = .reflowableText
            }
        }
        if reduceMotion {
            for mode in offered where mode.isAnimatedTransition {
                unavailable[mode] = .reduceMotion
            }
        }
        self.unavailable = unavailable

        // Falling back rather than rewriting. Every reason a choice may not run is a
        // condition of the moment: a setting can be turned off, the next device may be
        // able to curl, and the next publication may not reflow.
        var effective = chosen
        if effective == .pageCurl, !canCurl { effective = .slide }
        effective = effective.honoring(reduceMotion: reduceMotion)
        // Content last, and deliberately so. It is the only constraint nothing can work
        // around, so it has to survive the substitutions rather than precede them:
        // Reduce Motion turns Slide into Fast fade, and over reflowable text Fast fade
        // is itself impossible. Checking content first left `effective` naming a mode
        // this publication refuses.
        if isReflowable, effective.needsARasteredPage { effective = .slide }
        self.effective = effective
    }

    /// Whether a row can be picked.
    public func isAvailable(_ mode: PageTransition) -> Bool { unavailable[mode] == nil }
}

extension PageTransition {
    /// Whether this mode animates a *picture* of a page rather than the page itself.
    ///
    /// Both of them deform or dissolve a surface, and a surface is a texture. Over a
    /// comic that costs nothing, because the page is already an image; over reflowable
    /// text it needs the page rastered first, which is why these two are the modes an
    /// EPUB cannot yet offer.
    public var needsARasteredPage: Bool { self == .pageCurl || self == .fastFade }

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
