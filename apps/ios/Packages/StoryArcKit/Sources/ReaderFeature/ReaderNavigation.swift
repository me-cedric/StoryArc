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

    /// One slot past the last page in reading order, for Slide and Scroll to reach on a
    /// swipe or a scroll with nothing left to turn to. See ``endSlotPosition``.
    var endSlot: Int { endSlotPosition(slotCount: layout.count, isRightToLeft: isRightToLeft) }

    /// Moves back off `endSlot`, invisibly, once the end screen closes.
    ///
    /// Slide and Scroll actually moved into `endSlot` to reach the end screen; Curl and a
    /// tap or a key did not, because `turn(by:)` refuses before advancing past the last
    /// page. Only the first two need this, and the guard is what tells them apart.
    func snapBackFromEndSlot() {
        guard displayIndex == endSlot, !model.pages.isEmpty else { return }
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { displayIndex = displayIndex(forModel: model.pages.count - 1) }
    }

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
    /// `comic-reader` scopes the pairing to landscape itself. A continuous scroll is out
    /// because it has no facing pages to pair — it has a strip.
    ///
    /// **Curl is in, since D14.** The shader takes one texture, so the slot's two pages are
    /// composited into one before it ever sees them (``SpreadTexture``). Which modes pair is
    /// ``PageTransition/pairsPages``, so the two platforms answer it once.
    var isPairing: Bool {
        isLandscape && model.transitions(reduceMotion: reduceMotion).effective.pairsPages
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

/// The display position of the slot past the last page.
///
/// `comic-reader`: "a swipe or a scroll past the last page reaches the end screen". Past
/// the last page *in reading order*: after the run in left-to-right, and before it under
/// right-to-left, where the display order is reversed and the last page is position 0. A
/// slot after the run there sits beyond page one, and a swipe back from page one opened
/// the end screen. Android's `endSlotPosition` is the same rule.
func endSlotPosition(slotCount: Int, isRightToLeft: Bool) -> Int {
    isRightToLeft ? -1 : slotCount
}

/// The display position one reading-order step from `displayIndex`, or `nil` past
/// either end of the publication.
///
/// `readingOrderStep` already carries the right-to-left mirroring a tap or a key turns
/// with; the curl's beneath and previous sheets need the same step, because "forward"
/// and "backward" mean reading order to a reader whichever way the pages are laid out
/// on screen — a raw `displayIndex + 1` is the *previous* page in reading order once
/// right-to-left has reversed the display order. Android's `adjacentDisplayIndex` in
/// `Paging.kt` is the same rule.
func adjacentDisplayIndex(
    from displayIndex: Int,
    steps: Int,
    slotCount: Int,
    isRightToLeft: Bool
) -> Int? {
    let candidate = displayIndex + readingOrderStep(steps, isRightToLeft: isRightToLeft)
    return (0..<slotCount).contains(candidate) ? candidate : nil
}
