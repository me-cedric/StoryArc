import Testing

@testable import StoryArcCore

/// Where a continuous scroll draws a line between one page and the next.
///
/// `comic-reader`, *Continuous scroll*:
///
/// > **THEN** pages are stitched with no gap by default, with an option to show a separator
///
/// One sentence carrying three rules, and this suite asserts all three: a publication nobody
/// has told opens stitched, a reader who asks for the separator gets it, and it is drawn
/// *between* pages — never above the first one, where a band is a margin rather than a seam.
///
/// The rule used to be a condition inside each platform's scroll container, where no test
/// could reach it. It is `ShelfSettings.showsSeparator(above:)` now, and both the container
/// and this suite call it.
@Suite("A continuous scroll is stitched unless a separator is asked for")
struct ContinuousScrollTests {

    @Test("A publication nobody has told is stitched with no gap")
    func stitchedByDefault() {
        let settings = ShelfSettings()
        #expect(settings.showsSeparator(above: 1) == false)
        #expect(settings.showsSeparator(above: 42) == false)
    }

    @Test("A reader who asks for the separator gets one between every pair of pages")
    func separatorWhenAsked() {
        let settings = ShelfSettings().settingPageSeparator(true)
        #expect(settings.showsSeparator(above: 1))
        #expect(settings.showsSeparator(above: 42))
    }

    /// A band above page one is a margin, not a separator — there is nothing above it to
    /// separate it from.
    @Test("The first page is never given a separator, however the setting stands")
    func neverAboveTheFirstPage() {
        #expect(ShelfSettings().settingPageSeparator(true).showsSeparator(above: 0) == false)
        #expect(ShelfSettings().showsSeparator(above: 0) == false)
    }
}
