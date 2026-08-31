internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

// Moving between the publications of a series, from inside the reader.
//
// `comic-reader`: "WHEN a publication has internal chapter markers, or is one chapter
// of a series THEN the reader offers previous and next chapter actions without
// returning to the library". A local library knows the second of those two — a series
// and its order — so a chapter here is a publication, and the row is absent entirely
// for a book that belongs to no series.
//
// Internal members rather than private, because `ReaderView.chrome` is in another file.
extension ReaderView {
    /// Previous and next chapter, as two named menu rows.
    ///
    /// Two icon-only glass pills over the page until now. Named here, because the neighbour
    /// of a chapter is a *publication* and its title is the only thing that says which one
    /// pressing this opens.
    @ViewBuilder
    var chapterRow: some View {
        chapterButton(
            previousInSeries,
            systemImage: "backward.end",
            titleKey: "reader.chapter.previous"
        )
        chapterButton(
            nextInSeries,
            systemImage: "forward.end",
            titleKey: "reader.chapter.next"
        )
    }

    /// One chapter row, disabled at the end of the run rather than absent.
    ///
    /// The first and the last issue of a series each have one neighbour, and a section that
    /// changed shape between them would move the other row under the finger. A disabled
    /// control also says there is nothing that way, which a missing one does not.
    ///
    /// `backward.end` and `forward.end` rather than a chevron: this is the track-skip
    /// idiom, and it does not have to mirror for a right-to-left publication — the
    /// series still runs from its first issue to its last whichever way its pages do.
    private func chapterButton(
        _ destination: Publication?,
        systemImage: String,
        titleKey: LocalizedStringKey
    ) -> some View {
        Button {
            guard let destination else { return }
            isShowingMenu = false
            onOpen(destination)
        } label: {
            LabeledContent {
                if let destination {
                    Text(verbatim: destination.displayTitle)
                        .lineLimit(1)
                }
            } label: {
                Label {
                    Text(titleKey, bundle: .module)
                } icon: {
                    Image(systemName: systemImage)
                }
            }
        }
        .disabled(destination == nil)
    }
}
