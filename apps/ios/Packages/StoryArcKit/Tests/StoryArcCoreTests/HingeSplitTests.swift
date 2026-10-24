import CoreGraphics
import Testing

@testable import StoryArcCore

/// `foldables-and-iphone-duo` 1.1 and 2.7: the hinge arithmetic of Android's
/// `HingeAvoidance.kt`, and the posture a reported fold gives.
///
/// The first ten cases are the cases of Android's `HingeAvoidanceTest`, number for number, so
/// that the two platforms keep one rule.
@Suite("A page and the fold")
struct HingeSplitTests {

    @Test("No hinge splits a spread into equal halves with no gap")
    func noHinge() {
        let split = hingeSpreadSplit(containerWidth: 800, hingeStart: nil, hingeEnd: nil)

        #expect(split == HingeSpreadSplit(leadingWidth: 400, gap: 0, trailingWidth: 400))
    }

    @Test("A hinge entirely past the container's own width is not a hinge to avoid")
    func hingePastTheEnd() {
        let split = hingeSpreadSplit(containerWidth: 800, hingeStart: 900, hingeEnd: 950)

        #expect(split.gap == 0)
        #expect(split.leadingWidth == 400)
    }

    @Test("A hinge entirely before the container's own start is not a hinge to avoid")
    func hingeBeforeTheStart() {
        #expect(hingeSpreadSplit(containerWidth: 800, hingeStart: -100, hingeEnd: -20).gap == 0)
    }

    @Test("A centred hinge gives each half the room up to its own edge")
    func centredHinge() {
        let split = hingeSpreadSplit(containerWidth: 800, hingeStart: 380, hingeEnd: 420)

        #expect(split == HingeSpreadSplit(leadingWidth: 380, gap: 40, trailingWidth: 380))
    }

    @Test("A hinge nearer the start gives the trailing half the room")
    func hingeNearTheStart() {
        let split = hingeSpreadSplit(containerWidth: 800, hingeStart: 100, hingeEnd: 140)

        #expect(split == HingeSpreadSplit(leadingWidth: 100, gap: 40, trailingWidth: 660))
    }

    @Test("A hinge that only partly overlaps the container is clamped to it")
    func hingeClamped() {
        let split = hingeSpreadSplit(containerWidth: 800, hingeStart: -50, hingeEnd: 50)

        #expect(split == HingeSpreadSplit(leadingWidth: 0, gap: 50, trailingWidth: 750))
    }

    @Test("No hinge to split on means no inset")
    func noInset() {
        #expect(hingeInset(hingeSpreadSplit(containerWidth: 800, hingeStart: nil, hingeEnd: nil)) == nil)
    }

    @Test("A hinge nearer the start insets a single page onto the trailing side")
    func insetOntoTheTrailingSide() {
        let inset = hingeInset(hingeSpreadSplit(containerWidth: 800, hingeStart: 100, hingeEnd: 140))

        #expect(inset == HingeInset(width: 660, atStart: false))
    }

    @Test("A hinge nearer the end insets a single page onto the leading side")
    func insetOntoTheLeadingSide() {
        let inset = hingeInset(hingeSpreadSplit(containerWidth: 800, hingeStart: 660, hingeEnd: 700))

        #expect(inset == HingeInset(width: 660, atStart: true))
    }

    @Test("A centred hinge breaks its tie to the leading side")
    func tieGoesToTheLeadingSide() {
        let inset = hingeInset(hingeSpreadSplit(containerWidth: 800, hingeStart: 380, hingeEnd: 420))

        #expect(inset == HingeInset(width: 380, atStart: true))
    }

    // MARK: - The posture (2.7, 2.3, 2.4)

    /// The open display of an iPhone Duo, 669 by 951 points, with the fold down its middle.
    private let inner = CGRect(x: 0, y: 0, width: 669, height: 951)
    private let verticalFold = CGRect(x: 328.5, y: 0, width: 12, height: 951)
    /// The same display turned on its side, half open on a table.
    private let turned = CGRect(x: 0, y: 0, width: 951, height: 669)
    private let horizontalFold = CGRect(x: 0, y: 328.5, width: 951, height: 12)

    @Test("No fold reported draws the flat layout")
    func noFoldIsFlat() {
        #expect(FoldPosture.of(nil) == .flat)
        #expect(FoldPosture.of(DeviceFold(division: nil, isHalfOpen: true)) == .flat)
    }

    @Test("A fold that is fully open is flat, with the fold still reported")
    func fullyOpenIsFlat() {
        #expect(FoldPosture.of(DeviceFold(division: verticalFold, isHalfOpen: false)) == .flat)
    }

    @Test("Half open with the fold upright is a book, and with the fold across is a table")
    func halfOpen() {
        #expect(FoldPosture.of(DeviceFold(division: verticalFold, isHalfOpen: true)) == .book)
        #expect(FoldPosture.of(DeviceFold(division: horizontalFold, isHalfOpen: true)) == .tabletop)
    }

    @Test("A vertical fold across the surface is the one a page moves off")
    func verticalSpan() {
        let fold = DeviceFold(division: verticalFold, isHalfOpen: false)

        #expect(fold.verticalSpan(in: inner) == 328.5...340.5)
        #expect(DeviceFold(division: horizontalFold, isHalfOpen: false).verticalSpan(in: turned) == nil)
        // Converted into the surface's own terms: a surface that starts 100 points in.
        #expect(fold.verticalSpan(in: inner.offsetBy(dx: 100, dy: 0)) == 228.5...240.5)
    }

    // MARK: - Controls clear of the reserved regions (1.4)

    /// A camera cut-out at the top of the open display.
    private let camera = CGRect(x: 300, y: 0, width: 69, height: 38)

    /// The two reader controls: 45 points square, 16 in from the top corners of `area`.
    private func controls(in area: CGRect) -> [CGRect] {
        [
            CGRect(x: area.minX + 16, y: area.minY + 16, width: 45, height: 45),
            CGRect(x: area.maxX - 61, y: area.minY + 16, width: 45, height: 45),
        ]
    }

    @Test("No control sits under the camera or the fold, in any posture")
    func controlsAvoidTheRegions() {
        let cases: [(CGRect, DeviceFold)] = [
            (inner, DeviceFold(division: verticalFold, occlusions: [camera], isHalfOpen: false)),
            (inner, DeviceFold(division: verticalFold, occlusions: [camera], isHalfOpen: true)),
            (turned, DeviceFold(division: horizontalFold, occlusions: [camera], isHalfOpen: true)),
        ]
        for (bounds, fold) in cases {
            for control in controls(in: fold.controlArea(in: bounds)) {
                for region in fold.occlusions + [fold.division].compactMap(\.self) {
                    #expect(!control.intersects(region), "\(control) is under \(region) in \(fold)")
                }
                #expect(bounds.contains(control))
            }
        }
    }

    @Test("Half open on a table, the controls take the lower half and the page the upper")
    func tabletopHalves() {
        let fold = DeviceFold(division: horizontalFold, isHalfOpen: true)

        #expect(fold.controlArea(in: turned) == CGRect(x: 0, y: 340.5, width: 951, height: 328.5))
        #expect(fold.pageHeight(in: turned) == 328.5)
        #expect(DeviceFold(division: verticalFold, isHalfOpen: true).pageHeight(in: inner) == nil)
    }

    @Test("A camera already inside the safe area takes nothing more from the controls")
    func cameraAboveTheSurface() {
        let surface = CGRect(x: 0, y: 62, width: 402, height: 778)
        let fold = DeviceFold(division: nil, occlusions: [CGRect(x: 150, y: 11, width: 102, height: 37)])

        #expect(fold.controlArea(in: surface) == surface)
    }
}
