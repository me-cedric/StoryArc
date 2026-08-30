internal import SwiftUI

// The two orders a comic has, and the one place the reversal between them lives.
//
// Everything above and below this file counts pages the way the file does; the pager,
// the scroll and the curl count display positions, which run the other way in a
// right-to-left publication. Split out of `ReaderView` so that file stays the screen and
// its state rather than the screen plus the arithmetic. Android's `Paging.kt` carries the
// same note for the same reason.
//
// The members are internal rather than private because `ReaderView.body` is in another
// file, and a `private` member of an extension cannot be reached from it.
extension ReaderView {
    var isRightToLeft: Bool { model.readingDirection == .rightToLeft }

    /// Display positions, in the order the pager lays them out.
    ///
    /// One per *slot*. In portrait a slot is a page and this is the page list; in
    /// landscape a slot may hold two, and a turn crosses both at once — which is what
    /// `comic-reader` means by a pair being "never split across two turns".
    var displayOrder: [Int] { Array(layout.slots.indices) }

    /// The slot a display position holds.
    ///
    /// The only place the right-to-left reversal lives. Everything above and below this
    /// line counts the way the publication does.
    func slotIndex(forDisplay displayIndex: Int) -> Int {
        isRightToLeft ? layout.count - 1 - displayIndex : displayIndex
    }

    /// A display position turned back into the publication's own page number.
    ///
    /// The first page of the slot in *reading* order, which is the page the counter, the
    /// slider and `reading-progress` all mean.
    func modelIndex(forDisplay displayIndex: Int) -> Int {
        layout[slotIndex(forDisplay: displayIndex)]?.leading ?? 0
    }

    func displayIndex(forModel index: Int) -> Int {
        let slot = layout.slot(containing: index)
        return isRightToLeft ? layout.count - 1 - slot : slot
    }

    /// Whether two pages can share the screen.
    ///
    /// `comic-reader` scopes the pairing to landscape itself. Curl is out because the
    /// shader takes one decoded page and compositing two into a single texture is a
    /// different piece of work; a continuous scroll is out because it has no facing
    /// pages to pair — it has a strip.
    var isPairing: Bool {
        guard isLandscape else { return false }
        switch model.transitions(reduceMotion: reduceMotion).effective {
        case .slide, .fastFade: return true
        case .pageCurl, .verticalScroll, .horizontalScroll: return false
        }
    }

    /// What the page grouping depends on, so it is rebuilt when one of them moves and
    /// not on every layout pass.
    ///
    /// `wideIndices` only ever grows, so its count is enough to notice a change without
    /// hashing the set itself.
    var layoutKey: String {
        "\(isPairing)-\(model.pages.count)-\(model.wideIndices.count)"
            + "-\(model.settings.offsetsSpreads)"
    }

    /// Regroups the pages, and keeps the reader on the page it was reading.
    ///
    /// The *page*, not the slot: shifting the pairing or turning the device changes
    /// which slot a page lives in, and a reader who rotates their phone should still be
    /// looking at what they were looking at.
    func rebuildLayout() {
        layout = isPairing
            ? .paired(
                pageCount: model.pages.count,
                wide: model.wideIndices,
                isOffset: model.settings.offsetsSpreads
            )
            : .single(pageCount: model.pages.count)
        displayIndex = displayIndex(forModel: model.currentIndex)
    }
}
