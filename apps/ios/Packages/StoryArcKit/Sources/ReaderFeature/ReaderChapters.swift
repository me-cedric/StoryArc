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
    /// Previous and next chapter, or nothing at all when there is no series.
    @ViewBuilder
    var chapterRow: some View {
        if previousInSeries != nil || nextInSeries != nil {
            HStack(spacing: StoryArcSpace.sm) {
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
        }
    }

    /// One chapter button, disabled at the end of the run rather than absent.
    ///
    /// The first and the last issue of a series each have one neighbour, and a row that
    /// changed shape between them would move the other button under the finger. A
    /// disabled control also says there is nothing that way, which a missing one does not.
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
            onOpen(destination)
        } label: {
            Label {
                Text(titleKey, bundle: .module)
            } icon: {
                Image(systemName: systemImage)
            }
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.glass)
        .tint(.white)
        .disabled(destination == nil)
    }
}
