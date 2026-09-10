import Foundation
import Testing

@testable import ReaderFeature

/// That the page bends, and that the bend is the same bend on both platforms.
///
/// `page-transitions`: the turning page "curves as it goes, so the reader sees a sheet
/// bending rather than a picture folding". The reader asked for it in their own words —
/// "the curl doesn't follow the finger, the page turns flat, if it's possible I'd like the
/// curl to follow the movement a bit like a magazine page turns".
///
/// **The sample points and the expected values in ``band`` are the cross-platform
/// contract.** Android's `PageRollTest` asserts the same table, which is how the two
/// shaders are held to one projection when neither test process has a GPU in it. Change a
/// number here and the Android suite fails until it is changed there, which is the point.
@Suite("A page rolls")
struct PageRollTests {

    private let width: Double = 1000
    private let height: Double = 1600
    private let crease: Double = 0.06
    private let shadow: Double = 0.05
    private let back: Double = 0.55

    /// What the lip shows a third of the way across it, at three progresses.
    ///
    /// The material is a distance from the fold, because the fold itself moves with the
    /// progress and with the lean. Android's `PageRollTest.BAND` holds the same numbers.
    private struct Expected {
        let progress: Double
        let material: Double
        let shade: Double
    }

    private let band = [
        Expected(progress: 0.25, material: 79.25, shade: 0.5296),
        Expected(progress: 0.5, material: 112.07, shade: 0.5296),
        Expected(progress: 0.75, material: 79.25, shade: 0.5296),
    ]

    private func at(x: Double, y: Double = 800, progress: Double) -> PageRoll.Sample {
        PageRoll.sample(
            x: x,
            y: y,
            width: width,
            height: height,
            progress: progress,
            crease: crease,
            shadow: shadow,
            back: back
        )
    }

    private func radius(_ progress: Double) -> Double {
        PageRoll.radius(width: width, progress: progress)
    }

    private func fold(_ progress: Double, y: Double = 800) -> Double {
        PageRoll.fold(
            width: width, height: height, progress: progress, y: y, radius: radius(progress)
        )
    }

    @Test("The radius grows from nothing, peaks halfway, and is gone by the end")
    func radiusOverTheTurn() {
        #expect(radius(0) == 0)
        #expect(abs(radius(0.5) - PageRoll.radiusMax * width) < 0.001)
        #expect(radius(1) < 0.01)
        #expect(radius(0.25) < radius(0.5))
    }

    @Test("At rest and at the end the page is exactly the fold it replaces")
    func theEndsAreUnchanged() {
        // The two frames a reader sees most: a page lying flat, and a page just landed.
        let flat = at(x: 400, progress: 0)
        #expect(flat.region == .front)
        #expect(abs(flat.material - 400) < 0.001)
        #expect(flat.shade == 1)

        // A completed turn: the fold has reached the spine, the sheet has gone with it, and
        // what shows is the page beneath — undimmed, because the lip that cast the shadow
        // has no radius left.
        let done = at(x: 400, progress: 1)
        #expect(done.region == .under)
        #expect(abs(done.shade - 1) < 0.001)
    }

    @Test("The lip stands to the right of the fold, over the page beneath")
    func theLipStandsRightOfTheFold() {
        let progress = 0.5
        let radius = radius(progress)
        let fold = fold(progress)

        #expect(at(x: fold + 1, progress: progress).region == .lip)
        #expect(at(x: fold + radius / 2, progress: progress).region == .lip)
        #expect(at(x: fold + radius + 1, progress: progress).region == .under)
    }

    @Test("A point in the band is neither the flat face nor the flat back")
    func theBandIsItsOwnSurface() {
        // The pixel assertion the roll exists for, at the three progresses the change asks
        // for. What the point shows is compared with what a fold would have put there: the
        // same point mirrored, at the flat back's shading. Both have to differ, because a
        // bend both moves the texture and turns the surface away from the light.
        for expected in band {
            let progress = expected.progress
            let radius = radius(progress)
            let fold = fold(progress)
            let x = fold + radius / 3
            let sample = at(x: x, progress: progress)

            #expect(sample.region == .lip, "At \(progress) the point is not on the lip.")
            #expect(
                abs((sample.material - fold) - expected.material) < 0.5,
                "The lip's material at \(progress) moved. Android asserts this same number."
            )
            #expect(
                abs(sample.shade - expected.shade) < 0.005,
                "The lip's shading at \(progress) moved. Android asserts this same number."
            )
            // And neither is what a fold would have drawn there.
            #expect(abs(sample.material - (2 * fold - x)) > 0.5)
            #expect(abs(sample.shade - back) > 0.005)
        }
    }

    @Test("The lip's shading runs from the flat back face at its top to a dark rim")
    func theLipIsShadedAcross() {
        let progress = 0.5
        let radius = radius(progress)
        let fold = fold(progress)

        // Continuous with the flat back face at the fold, which is the seam a reader would
        // see as a hard line if it were not.
        #expect(abs(at(x: fold, progress: progress).shade - back) < 0.005)
        // And edge-on at the rim, which is the page's thickness.
        #expect(abs(at(x: fold + radius, progress: progress).shade - back * PageRoll.rim) < 0.005)
    }

    @Test("The material is continuous across the seam between the lip and the flat back")
    func theSeamHasNoGap() {
        let progress = 0.5
        let radius = radius(progress)
        let fold = fold(progress)

        let lip = at(x: fold, progress: progress)
        let flat = at(x: fold - 0.01, progress: progress)

        #expect(lip.region == .lip)
        #expect(flat.region == .back)
        // Both are the material a half circumference along the sheet from the fold. A gap
        // here is a band of the page repeated or missing at the seam.
        #expect(abs(lip.material - (fold + .pi * radius)) < 0.1)
        #expect(abs(flat.material - (fold + .pi * radius)) < 0.1)
    }

    @Test("The silhouette across the band is not a vertical line")
    func theFoldLeans() {
        let progress = 0.5
        let radius = radius(progress)

        let top = fold(progress, y: 0)
        let middle = fold(progress, y: height / 2)
        let bottom = fold(progress, y: height)

        #expect(top > bottom, "The fold does not lean: \(top) at the top, \(bottom) at the foot.")
        #expect(abs((middle - bottom) - (top - middle)) < 0.01, "The lean is uneven.")
        #expect(abs((top - bottom) - PageRoll.lean * radius) < 0.01)
    }

    @Test("The shadow's leading edge follows the rim, so it is not a vertical line either")
    func theShadowLeansToo() {
        let progress = 0.5
        let radius = radius(progress)
        let topFold = fold(progress, y: 0)
        let footFold = fold(progress, y: height)

        #expect(at(x: topFold + radius, y: 0, progress: progress).region == .lip)
        #expect(at(x: footFold + radius, y: height, progress: progress).region == .lip)
        // The same point on the screen, at the two heights: one is under the sheet and the
        // other is in open shadow, which is only true because the edge leans.
        #expect(at(x: topFold + radius, y: height, progress: progress).region == .under)
    }

    @Test("The page beneath is not drawn at rest, which is how the wrong side announced itself")
    func nothingUnderneathAtRest() {
        // ADR-0009 records the first attempt at this shader drawing the page beneath at a
        // flat page's rest. Kept as a test because the failure was invisible until a second
        // page existed, and by then it read as a decode fault rather than as a projection.
        for x in [0.0, 250, 500, 750, 999] {
            #expect(at(x: x, progress: 0).region != .under, "At rest the page beneath shows at x=\(x).")
        }
    }
}
