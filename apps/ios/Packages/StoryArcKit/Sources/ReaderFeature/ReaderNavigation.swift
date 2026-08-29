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
    var displayOrder: [Int] { Array(model.pages.indices) }

    /// A display position turned back into the publication's own page number.
    func modelIndex(forDisplay displayIndex: Int) -> Int {
        model.readingDirection.position(displayIndex, of: model.pages.count)
    }

    /// A page number turned into the position the pager holds it at.
    ///
    /// The same mapping as above, because reversing a run is its own inverse. Named
    /// twice because the call sites mean two different things by it.
    func displayIndex(forModel index: Int) -> Int {
        model.readingDirection.position(index, of: model.pages.count)
    }

    var pageSlider: Binding<Double> {
        Binding(
            get: { Double(model.currentIndex) },
            set: { new in
                let index = Int(new.rounded())
                guard model.pages.indices.contains(index) else { return }
                displayIndex = displayIndex(forModel: index)
            }
        )
    }
}
