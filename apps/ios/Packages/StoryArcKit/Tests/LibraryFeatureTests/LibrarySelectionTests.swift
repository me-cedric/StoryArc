import Testing

@testable import LibraryFeature

/// What the reader has picked, as a value.
///
/// The number this counts is the library's **navigation title** for the whole of selection
/// mode — `collections-and-reading-lists` wants publications "selected in bulk from the
/// library", and the modern Apple answer states the count where a screen states its name,
/// so a bottom bar does not have to carry a label. Which means a count that is wrong is a
/// navigation bar that is lying, and it is worth asserting as a value rather than leaving
/// to a screenshot of one arbitrary number.
///
/// The chrome built on top of it is `BulkSelectionChromeTests`. Android asserts the same
/// two properties through its contextual top app bar, in `BulkSelectionChromeTest`, because
/// there the count is composed rather than computed.
@Suite("A selection counts what is picked and drops it on the way out")
struct LibrarySelectionTests {

    /// The count is what is picked, at nought, at one and at many.
    ///
    /// Nought is the case worth writing down: the mode can be entered without picking
    /// anything, the navigation title says so in words from the first frame, and a count
    /// that reported `1` for an empty set — or that could not be asked at all until
    /// something was picked — would put a lie there before the reader had done anything.
    @Test("The count is what is picked — nought, one and many")
    func theCountIsWhatIsPicked() {
        var selection = LibrarySelection()
        selection.begin()
        // Named rather than compared in place: `selection.count == 0` is what `empty_count`
        // rewrites to `isEmpty`, and `isEmpty` is not the thing under test — the number the
        // navigation title states is.
        let atNought = selection.count
        #expect(atNought == 0, "a selection just begun has picked nothing")

        selection.toggle("a")
        #expect(selection.count == 1)

        for id in ["b", "c", "d", "e"] { selection.toggle(id) }
        #expect(selection.count == 5)

        // And unpicking counts down again, so the title follows the set rather than
        // counting taps.
        selection.toggle("c")
        #expect(selection.count == 4)
        selection.toggle("c")
        #expect(selection.count == 5)
    }

    /// Leaving the mode gives the shelf back, and gives it back completely.
    ///
    /// `collections-and-reading-lists` asks for "a clear way out". One action, and it drops
    /// the mode *and* the picks: a reader who has finished picking has finished with both,
    /// and a library left holding a decision the reader abandoned is the state that would
    /// put the capsule back up holding it on the next tap.
    @Test("Leaving the mode drops the mode and the picks together")
    func leavingTheModeRestoresTheShelf() {
        var selection = LibrarySelection()
        selection.begin()
        for id in ["a", "b", "c"] { selection.toggle(id) }
        #expect(selection.isActive)
        #expect(selection.count == 3)

        selection.end()

        #expect(!selection.isActive, "the shelf is still in selection mode after Done")
        let afterDone = selection.count
        #expect(
            afterDone == 0,
            "the picks outlived the mode, so the chrome would come back holding them"
        )
    }
}
