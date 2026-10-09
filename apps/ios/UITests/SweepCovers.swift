import XCTest

@MainActor
extension XCTestCase {
    /// The covers a sweep may tap, and nothing that merely sits where a cover does.
    ///
    /// ``coversOnScreen(in:named:ofFormat:)`` filters `app.buttons` by position — a band
    /// between the toolbar and the tab bar — and on this device that band contains the
    /// skipped-publications notice's two controls. So a walk that asked for "the covers" and
    /// tapped the first two tapped *What couldn't be opened* and *Dismiss*, and the shelf
    /// stayed at `0 selected` while the walk reported the covers as unselectable.
    ///
    /// A cover's spoken label carries its format — `LibraryMarks.spoken([title, subtitle,
    /// format, …])` — and no notice does, so asking the shared helper for one format at a
    /// time is a filter it already has. Every format on the shelf, so this is still "the
    /// covers" rather than "the EPUBs".
    func realCovers(in app: XCUIApplication) -> [XCUIElement] {
        // `PublicationFormat.displayName`'s nine, which is the whole set — a cover with a
        // format this misses would be silently unpickable, which is the failure above again.
        let formats = ["CBZ", "CBR", "CB7", "CBT", "EPUB", "PDF", "Folder",
                       "M4B", "MP3", "FLAC", "Ogg", "Audiobook folder"]
        // **One snapshot of the hierarchy, not nine.** Asking the shared helper once per
        // format enumerated every button on the screen nine times over, and at
        // `accessibilityExtraExtraExtraLarge` — where a cell is 1.4 times wider, so the shelf
        // is taller and the tree deeper — that was most of a twenty-two-minute suite. Same
        // filter, one round trip to the app.
        let ceiling = app.frame.height - 100
        let isACover = { (element: XCUIElement) in
            element.isHittable
                && element.frame.midY > 150
                && element.frame.midY < ceiling
                && formats.contains { element.label.contains(", \($0)") }
        }
        let asButtons = app.buttons.allElementsBoundByIndex.filter(isACover)
        if !asButtons.isEmpty { return asButtons }
        // **In selection mode a cover may not be a button.** `CoverCell` drops the
        // `NavigationLink` for a plain view with an `onTapGesture` while the shelf is
        // picking, so what the accessibility tree calls it is the platform's decision rather
        // than this app's. Falling back rather than asserting: a walk that reported "no
        // covers" on a shelf full of them sent the last reader to the wrong file.
        return app.otherElements.allElementsBoundByIndex.filter(isACover)
    }
}
