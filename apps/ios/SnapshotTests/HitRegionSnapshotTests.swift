import DesignSystem
import SwiftUI
import XCTest

/// Task 27.1 of `close-the-audited-gaps` (decision O31): a larger touch area leaves the drawn
/// control at its system size.
///
/// Task 24.3 put `.hitRegion()` on the label of `.bordered` buttons, and the system drew its
/// capsule around the 44 pt label. A host test cannot see that, because a layout measure counts
/// the room and not the paint. This draws the buttons and measures the paint.
@MainActor
final class HitRegionSnapshotTests: XCTestCase {
    func testASmallBorderedButtonKeepsItsSystemSize() {
        let system = drawnBounds(
            of: Button {} label: { Text("Undo") }.buttonStyle(.bordered).controlSize(.small)
        )
        let grown = drawnBounds(
            of: Button {} label: { Text("Undo") }
                .buttonStyle(HitRegionButtonStyle(.bordered)).controlSize(.small)
        )

        XCTAssertFalse(system.isNull, "The system button drew nothing.")
        XCTAssertLessThan(system.height, 44, "A small bordered button is a capsule under 44 points.")
        XCTAssertEqual(grown.height, system.height, accuracy: 1, "The hit region changed the capsule's height.")
        XCTAssertEqual(grown.width, system.width, accuracy: 1, "The hit region changed the capsule's width.")
    }
}
