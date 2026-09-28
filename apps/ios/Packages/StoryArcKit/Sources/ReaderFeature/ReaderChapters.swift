internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// Moving between chapters, from inside the reader.
///
/// `comic-reader`, D4: previous and next chapter move *within* this publication first —
/// a comic's `ComicInfo` bookmarks, or a PDF's own outline where the platform exposes
/// one (PDFKit; Android has no outline, ADR-0012, so it reads `ComicInfo` alone) — and
/// open a neighbouring publication only past the first or last chapter. A series still
/// gives every publication in it a neighbour, which is the other half of `comic-reader`'s
/// "or is one chapter of a series".
///
/// A `View` of its own rather than a `ReaderView` extension: the PDF outline lives behind
/// an actor, so loading it needs `@State` and a `.task` of its own, and `ReaderView.swift`
/// is at the 400-line cap this project enforces.
struct ChapterActionsSection: View {
    let model: ReaderModel
    let previousInSeries: Publication?
    let nextInSeries: Publication?
    /// Jumps within this publication, and closes the menu.
    let onJump: (Int) -> Void
    /// Opens a neighbouring publication, and closes the menu.
    let onOpen: (Publication) -> Void

    /// A PDF's own outline, read once. `ComicInfo`'s bookmarks need no state at all —
    /// `model.archive` already has them synchronously.
    @State private var pdfChapterStarts: [Int] = []

    private var starts: [Int] { model.archive?.chapterStartIndices ?? pdfChapterStarts }

    var body: some View {
        Group {
            if previousInSeries != nil || nextInSeries != nil || !starts.isEmpty {
                Section {
                    chapterButton(
                        inPublication: ChapterNavigation.previousStart(from: model.currentIndex, starts: starts),
                        neighbour: previousInSeries,
                        systemImage: "backward.end",
                        titleKey: "reader.chapter.previous"
                    )
                    chapterButton(
                        inPublication: ChapterNavigation.nextStart(from: model.currentIndex, starts: starts),
                        neighbour: nextInSeries,
                        systemImage: "forward.end",
                        titleKey: "reader.chapter.next"
                    )
                }
            }
        }
        .task {
            guard let pdf = model.pdf else { return }
            pdfChapterStarts = PdfOutlineChapters.startIndices(await pdf.outline())
        }
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
        inPublication index: Int?,
        neighbour: Publication?,
        systemImage: String,
        titleKey: LocalizedStringKey
    ) -> some View {
        Button {
            if let index {
                onJump(index)
            } else if let neighbour {
                onOpen(neighbour)
            }
        } label: {
            LabeledContent {
                // Only a neighbouring publication has a title worth naming; a jump
                // within this one is still the book already on screen.
                if index == nil, let neighbour {
                    Text(verbatim: neighbour.displayTitle)
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
        .disabled(index == nil && neighbour == nil)
    }
}
