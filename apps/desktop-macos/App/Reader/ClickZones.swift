import Foundation

/// Where a click landed on a page, in the three zones a phone's tap uses.
enum ClickZone: Sendable, Equatable {
    case leading
    case middle
    case trailing
}

/// The edge click zones, on by default on a desktop.
///
/// `design.md` Open Question 2, answered by the owner: the zones are on by default, as the
/// `page-transitions` Turn triggers requirement has them on for a phone, and a reader turns
/// them off in the reader's settings. With the zones off every click is the middle, which
/// toggles the chrome, and no click turns a page. Task 2.12.
enum ClickZones {
    /// Each edge zone is a third of the width. A Mac-side copy of
    /// `ZoomablePage.edgeZoneFraction`, which is internal to `ReaderFeature`.
    static let edgeFraction: CGFloat = 1.0 / 3.0

    static func zone(atX x: CGFloat, width: CGFloat, zonesOn: Bool) -> ClickZone {
        guard zonesOn, width > 0 else { return .middle }
        let edge = width * edgeFraction
        if x < edge { return .leading }
        if x > width - edge { return .trailing }
        return .middle
    }

    /// The page step a zone asks for, mirrored in a right-to-left publication: the
    /// trailing edge of the screen is the next page left-to-right and the previous page
    /// right-to-left, because the zones are spatial, as the arrow keys are.
    static func step(for zone: ClickZone, isRightToLeft: Bool) -> Int {
        switch zone {
        case .middle: 0
        case .trailing: isRightToLeft ? -1 : 1
        case .leading: isRightToLeft ? 1 : -1
        }
    }
}

/// When the pointer and the chrome hide after the pointer rests.
///
/// `desktop-experience`, *Pointer reading*: three seconds, and the page does not move.
enum PointerIdle {
    static let hideAfter: Duration = .seconds(3)
}
