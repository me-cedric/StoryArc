internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

// How far through a book the reader is, said in one line.
//
// `ebook-reader`, *Progress display*: "one line states how far through the publication they
// are and how much of the current chapter is left, in words … no slider is offered, and the
// position is not drawn over the page."
//
// The line lives on the menu's contents row, which is also the way into the book's own
// navigation — a reader asking *where am I* is usually about to ask *where else could I be*.
//
// The members are internal rather than private because `EpubReaderMenu` is in another file.
extension EpubReaderView {

    /// The contents row: the position, in words, and the way to somewhere else.
    var progressRow: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
            Label {
                Text(LocalizedStringKey(ReaderMenuEntry.contents.titleKey), bundle: .module)
            } icon: {
                Image(systemName: ReaderMenuEntry.contents.systemImage)
            }
            progressText
                .textRole(.caption)
                .foregroundStyle(theme.palette.textSecondary)
        }
    }

    /// The position, as a sentence.
    ///
    /// A percentage, never a page number: `ebook-reader` is explicit that a reflowable page
    /// count is a function of the type size and must not be presented as an identity.
    var progressText: Text {
        Text("epub.progress \(Int((model.progression * 100).rounded()))", bundle: .module)
    }
}
