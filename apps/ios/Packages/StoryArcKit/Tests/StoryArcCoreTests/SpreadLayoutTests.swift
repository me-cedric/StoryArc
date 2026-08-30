import Testing

@testable import StoryArcCore

/// Which pages share a screen in landscape.
///
/// `comic-reader` states three rules — pair consecutive portrait pages, show a wide page
/// alone, and let the reader shift the pairing by one — and every one of them is
/// arithmetic. Android's `SpreadLayoutTest` asserts the same table.
@Suite("Spread layout")
struct SpreadLayoutTests {
    private func shape(_ layout: SpreadLayout) -> [[Int]] {
        layout.slots.map(\.pages)
    }

    @Test("Portrait shows every page on its own")
    func single() {
        #expect(shape(.single(pageCount: 4)) == [[0], [1], [2], [3]])
    }

    @Test("A publication with no pages has no slots")
    func empty() {
        #expect(SpreadLayout.single(pageCount: 0).slots.isEmpty)
        #expect(SpreadLayout.paired(pageCount: 0, wide: [], isOffset: true).slots.isEmpty)
    }

    @Test("Landscape pairs consecutive pages")
    func pairs() {
        #expect(shape(.paired(pageCount: 6, wide: [], isOffset: false)) == [[0, 1], [2, 3], [4, 5]])
    }

    @Test("An odd page count leaves the last page alone rather than dropping it")
    func oddTail() {
        #expect(shape(.paired(pageCount: 5, wide: [], isOffset: false)) == [[0, 1], [2, 3], [4]])
    }

    @Test("A wide page is shown alone, never split across two turns")
    func wideStandsAlone() {
        // Page 2 is declared a double-page spread, so it takes a slot of its own — and
        // page 3 cannot be paired backwards into it, so the run resumes at 3-4.
        #expect(
            shape(.paired(pageCount: 6, wide: [2], isOffset: false))
                == [[0, 1], [2], [3, 4], [5]]
        )
    }

    @Test("The page before a wide one is not paired into it")
    func neighbourOfAWideePage() {
        // Page 3 is wide, so page 2 has nothing to face and stands alone too.
        #expect(
            shape(.paired(pageCount: 6, wide: [3], isOffset: false))
                == [[0, 1], [2], [3], [4, 5]]
        )
    }

    @Test("Two wide pages in a row each stand alone")
    func consecutiveWidePages() {
        #expect(
            shape(.paired(pageCount: 4, wide: [1, 2], isOffset: false))
                == [[0], [1], [2], [3]]
        )
    }

    @Test("The offset stands the cover alone and shifts everything after it")
    func offset() {
        #expect(
            shape(.paired(pageCount: 6, wide: [], isOffset: true))
                == [[0], [1, 2], [3, 4], [5]]
        )
    }

    @Test("A page knows which slot it is in, on either side of a pair")
    func lookup() {
        let layout = SpreadLayout.paired(pageCount: 6, wide: [2], isOffset: false)
        #expect(layout.slot(containing: 0) == 0)
        #expect(layout.slot(containing: 1) == 0)
        #expect(layout.slot(containing: 2) == 1)
        #expect(layout.slot(containing: 4) == 2)
        #expect(layout.slot(containing: 5) == 3)
    }

    @Test("A page outside the publication resolves to the first slot rather than crashing")
    func lookupOutOfRange() {
        let layout = SpreadLayout.single(pageCount: 3)
        #expect(layout.slot(containing: 99) == 0)
        #expect(layout.slot(containing: -1) == 0)
        #expect(layout[99] == nil)
    }

    @Test("A publication of nothing but wide pages has no pairing to offset")
    func nothingToPair() {
        #expect(SpreadLayout.paired(pageCount: 3, wide: [0, 1, 2], isOffset: false).hasPairs == false)
        #expect(SpreadLayout.paired(pageCount: 4, wide: [], isOffset: false).hasPairs)
        #expect(SpreadLayout.single(pageCount: 4).hasPairs == false)
    }
}
