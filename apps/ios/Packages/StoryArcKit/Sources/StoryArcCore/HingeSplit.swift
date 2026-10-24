public import CoreGraphics

/// Keeping a reader's page off the fold of a foldable display.
///
/// `native-experience`, *Foldable devices*: a single page is shown whole on one side of the fold,
/// and a spread puts its gutter on it. This is Android's `HingeAvoidance.kt`, ported line for
/// line, so that one rule holds on both platforms. `HingeSplitTests` asserts the cases of
/// Android's `HingeAvoidanceTest`.
///
/// Plain numbers in and out. iOS 27.1 reports the fold as a `ReservedRegion` of kind
/// `.division`, which has no public initializer. So the reader turns it into a ``DeviceFold``
/// at the edge, and a test or a snapshot hands one in.

/// A two-up spread's width split across a hinge: the two halves, and the gap between them.
public struct HingeSpreadSplit: Equatable, Sendable {
    public let leadingWidth: CGFloat
    public let gap: CGFloat
    public let trailingWidth: CGFloat

    public init(leadingWidth: CGFloat, gap: CGFloat, trailingWidth: CGFloat) {
        self.leadingWidth = leadingWidth
        self.gap = gap
        self.trailingWidth = trailingWidth
    }
}

/// How a two-up spread splits across a hinge that falls inside its own container.
///
/// Equal halves and no gap when there is nothing to split on: no hinge, or a hinge that misses
/// this container.
///
/// - Parameters:
///   - containerWidth: the full width the spread draws across.
///   - hingeStart: the hinge's near edge, from this container's own leading edge, or `nil`.
///   - hingeEnd: the hinge's far edge. Ignored when `hingeStart` is `nil`.
public func hingeSpreadSplit(containerWidth: CGFloat, hingeStart: CGFloat?, hingeEnd: CGFloat?) -> HingeSpreadSplit {
    let half = max(containerWidth / 2, 0)
    let noHinge = HingeSpreadSplit(leadingWidth: half, gap: 0, trailingWidth: half)
    guard let hingeStart, let hingeEnd else { return noHinge }
    let start = min(max(hingeStart, 0), containerWidth)
    let end = min(max(hingeEnd, 0), containerWidth)
    guard end > start else { return noHinge }
    return HingeSpreadSplit(leadingWidth: start, gap: end - start, trailingWidth: containerWidth - end)
}

/// Where a single page sits so it never straddles a hinge: a width, and which edge it is pinned to.
public struct HingeInset: Equatable, Sendable {
    public let width: CGFloat
    public let atStart: Bool

    public init(width: CGFloat, atStart: Bool) {
        self.width = width
        self.atStart = atStart
    }
}

/// The inset for a single page, from an already-computed `split`.
///
/// `nil` means draw the page as on a flat display, because `split` found nothing to avoid.
/// Otherwise the page goes to the side with more room, at that side's width. A tie goes to the
/// leading side.
public func hingeInset(_ split: HingeSpreadSplit) -> HingeInset? {
    guard split.gap > 0 else { return nil }
    return split.leadingWidth >= split.trailingWidth
        ? HingeInset(width: split.leadingWidth, atStart: true)
        : HingeInset(width: split.trailingWidth, atStart: false)
}

/// What a foldable display reports: the fold, the camera and the hinge.
///
/// Every frame is in global coordinates, so that each view puts it in its own terms. A device
/// with no fold reports no ``DeviceFold`` at all, and the reader draws its flat layout.
public struct DeviceFold: Equatable, Sendable {
    /// The `.division` region: the fold, while it divides the display.
    public var division: CGRect?
    /// The `.occlusion` regions: the camera and anything else that covers the display.
    public var occlusions: [CGRect]
    /// Whether the hinge reports `.partiallyOpen`.
    public var isHalfOpen: Bool

    public init(division: CGRect?, occlusions: [CGRect] = [], isHalfOpen: Bool = false) {
        self.division = division
        self.occlusions = occlusions
        self.isHalfOpen = isHalfOpen
    }

    /// The fold's horizontal span in the terms of `surface`, when the fold runs top to bottom.
    public func verticalSpan(in surface: CGRect) -> ClosedRange<CGFloat>? {
        guard let division, division.height > division.width else { return nil }
        return (division.minX - surface.minX)...(division.maxX - surface.minX)
    }

    /// The height of the upper half of `surface` on a table, or `nil` in every other posture.
    public func pageHeight(in surface: CGRect) -> CGFloat? {
        guard FoldPosture.of(self) == .tabletop, let division else { return nil }
        return max(division.minY - surface.minY, 0)
    }

    /// Where a control may go in `surface`: clear of every occlusion and, on a table, below the
    /// fold. In global coordinates, like `surface`.
    ///
    /// A region in the upper half of the area pushes the controls down; one in the lower half
    /// pushes them up. A vertical fold is not counted: the controls sit in the corners, and a
    /// fold down the middle never reaches them.
    public func controlArea(in surface: CGRect) -> CGRect {
        var top = surface.minY
        var bottom = surface.maxY
        if FoldPosture.of(self) == .tabletop, let division { top = max(top, division.maxY) }
        for region in occlusions where region.intersects(surface) {
            if region.midY < (top + bottom) / 2 {
                top = max(top, region.maxY)
            } else {
                bottom = min(bottom, region.minY)
            }
        }
        return CGRect(x: surface.minX, y: top, width: surface.width, height: max(bottom - top, 0))
    }
}

/// How the device is held, from what it reports.
public enum FoldPosture: Sendable {
    /// No fold, a fold that is fully open, or nothing reported: the layout of a flat display.
    case flat
    /// Half open with the fold upright, held like a book.
    case book
    /// Half open with the fold across, lying on a table.
    case tabletop

    /// `native-experience`, *The device cannot report its posture*: no fold, no hinge or no
    /// region is the flat layout, and nothing waits for a posture.
    public static func of(_ fold: DeviceFold?) -> FoldPosture {
        guard let fold, fold.isHalfOpen, let division = fold.division else { return .flat }
        return division.height > division.width ? .book : .tabletop
    }
}
