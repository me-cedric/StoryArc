internal import CoreGraphics
internal import SwiftUI

internal import StoryArcCore

/// Which container draws the pages, and why the reversal happens where it does.
///
/// Split from `ReaderView.swift` when that file passed the length the linter allows.
/// The chrome, the gestures and the body stayed there; the container choice came here.
extension ReaderView {

    /// The pages themselves, in whichever container the chosen mode calls for.
    ///
    /// `page-transitions` treats the mode as a property of the container, and this is
    /// what that means here: Slide is a `TabView`, Fast fade is one page with a
    /// dissolve, and Scroll is a `ScrollView` of stitched pages. One `displayIndex`
    /// drives all three — on iOS `scrollPosition` and `TabView`'s selection speak the
    /// same language, so there is no coordinator type to write. Android needs one.
    ///
    /// Right-to-left reverses the *display* order and maps the index at the
    /// boundary, so the model keeps counting pages the way the publication does
    /// and the indicator says "2 of 4" rather than "3 of 4" for the same page.
    ///
    /// The obvious alternative — mirroring the pager with a `scaleEffect` of -1 —
    /// was tried and does not work: `TabView`'s paging gesture is computed before
    /// the transform, so a swipe pages the wrong way, jumps two at a time, and
    /// then sticks at an end. Reversing the data is the mechanism that survives
    /// contact with the gesture recogniser.
    @ViewBuilder
    func pages(in size: CGSize) -> some View {
        let choices = model.transitions(reduceMotion: reduceMotion)
        let container = Group {
            switch choices.effective {
            case .verticalScroll: stitched(.vertical)
            case .horizontalScroll: stitched(.horizontal)
            case .fastFade: faded
            case .pageCurl: curled
            case .slide: paged
            }
        }
        container
            // One direction only: the container moves, the model follows.
            .onChange(of: displayIndex) { _, new in
                let index = modelIndex(forDisplay: new)
                guard model.pages.indices.contains(index) else { return }
                // Reading back to where a jump started retires the offer to go there.
                pageReturn = pageReturn.moved(to: index)
                Task { await model.go(to: index) }
            }
            // And once, the other way, when the publication opens on a page that is
            // not the first — a ComicInfo cover, or a resumed position later.
            .onAppear { displayIndex = displayIndex(forModel: model.currentIndex) }
            // `comic-reader`: a direction change "applies immediately without losing the
            // current page". The run the pager lays out reverses under the reader, so the
            // position holding the page they are on moves to the other end of it. Asked
            // again here, or turning a manga around would leave them the same distance
            // from the other cover.
            //
            // Not animated, because this is not a turn: the page in front of the reader
            // does not change, only where the pager keeps it, and animating that would
            // fling across the publication to arrive back where it started.
            .onChange(of: model.readingDirection) { _, _ in
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) {
                    displayIndex = displayIndex(forModel: model.currentIndex)
                }
            }
            .accessibilityLabel(
                isRightToLeft ? Text("reader.rightToLeft", bundle: .module) : Text(verbatim: "")
            )
    }
}
