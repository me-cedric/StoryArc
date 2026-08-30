import CoreGraphics
import Testing

@testable import Formats
@testable import ReaderFeature

/// Mirrors Android's `PdfPageOverlayTest`, assertion for assertion.
///
/// The conversion between a page and the view fitting it, and the flattening of an outline.
/// Both are arithmetic over values, so both are asserted on the host rather than on a device —
/// which is the whole reason they are free functions rather than methods on a scroll view.
///
/// Two cases differ from the Android suite, and neither is a gap. The outline is here and not
/// there, because that platform's PDF API exposes none (ADR-0012). And Android asserts an
/// *unprojection* that has no mirror here: its page is transformed by a `graphicsLayer`, so a
/// finger reports screen coordinates, while `UIScrollView` reports a touch already in the
/// content's own space.
@Suite("PDF page overlay")
struct PdfPageOverlayTests {

    /// A portrait page in a landscape view: bars either side, and none above or below.
    private let page = CGSize(width: 200, height: 300)
    private let view = CGSize(width: 400, height: 300)

    @Test("The page sits centred inside the view that is fitting it")
    func pageIsCentred() {
        let rect = pageRect(of: page, in: view)
        #expect(rect == CGRect(x: 100, y: 0, width: 200, height: 300))
    }

    @Test("A view with no size has no page in it")
    func noViewNoPage() {
        #expect(pageRect(of: page, in: .zero) == .zero)
        #expect(pageRect(of: .zero, in: view) == .zero)
    }

    @Test("A point on the page is reported as the fraction of it")
    func pointIsNormalised() {
        // The middle of the artwork, which is not the middle of the view's left half.
        let middle = normalisedPoint(CGPoint(x: 200, y: 150), imageSize: page, in: view)
        #expect(middle == CGPoint(x: 0.5, y: 0.5))
    }

    @Test("A point in the bar beside the page is clamped to the page's edge")
    func pointIsClamped() {
        let left = normalisedPoint(CGPoint(x: 0, y: 150), imageSize: page, in: view)
        #expect(left.x == 0)
        let right = normalisedPoint(CGPoint(x: 400, y: 150), imageSize: page, in: view)
        #expect(right.x == 1)
    }

    @Test("A normalised rectangle lands back where it came from")
    func rectRoundTrips() {
        let mark = CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.1)
        let drawn = viewRect(mark, imageSize: page, in: view)
        #expect(drawn == CGRect(x: 150, y: 150, width: 100, height: 30))
    }

    @Test("An outline is flattened in reading order, carrying its depth")
    func outlineIsFlattened() {
        let rows = PdfOutlineRow.rows(of: [
            PdfOutlineItem(
                title: "One",
                pageIndex: 0,
                children: [
                    PdfOutlineItem(title: "One point one", pageIndex: 1, children: [])
                ]
            ),
            PdfOutlineItem(title: "Two", pageIndex: 2, children: []),
        ])
        #expect(rows.map(\.title) == ["One", "One point one", "Two"])
        #expect(rows.map(\.depth) == [0, 1, 0])
        #expect(rows.map(\.page) == [0, 1, 2])
    }

    @Test("An entry whose destination is unresolvable is still a row")
    func unresolvedOutlineEntry() {
        let rows = PdfOutlineRow.rows(of: [
            PdfOutlineItem(title: "Nowhere", pageIndex: nil, children: [])
        ])
        #expect(rows.count == 1)
        #expect(rows.first?.page == nil)
    }

    @Test("An outline with nothing in it flattens to nothing")
    func emptyOutline() {
        #expect(PdfOutlineRow.rows(of: []).isEmpty)
    }
}
