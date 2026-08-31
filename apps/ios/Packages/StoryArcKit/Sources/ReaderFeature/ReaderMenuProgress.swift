internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

// Where the reader is, and everywhere else they could be, on one row.
//
// `comic-reader`, *Where the reader is, at a glance*: "the coarse position through the
// publication is drawn as a fill behind the menu's own contents row, and stated in text on
// that row … the text is what conveys the position, so the fill may be absent without
// anything being lost".
//
// The row is also the way into the publication's own navigation: the thumbnail browser for
// a comic, the outline for a PDF that carries one. One row for *where am I* and *where else
// could I be*, because a reader asking the first question is usually about to ask the
// second.
//
// The members are internal rather than private because `ReaderMenu` is in another file.
extension ReaderView {

    /// The contents row: the position, in text, and the way to somewhere else.
    var contentsRow: some View {
        Button { openContents() } label: {
            VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                Label {
                    Text(LocalizedStringKey(ReaderMenuEntry.contents.titleKey), bundle: .module)
                } icon: {
                    Image(systemName: ReaderMenuEntry.contents.systemImage)
                }
                positionText
                    .textRole(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        // One element, spoken once. The position is a second line of this row rather than a
        // separate thing to swipe to, and `comic-reader` is explicit that "the text is what
        // conveys the position".
        .accessibilityElement(children: .combine)
    }

    /// Where this publication's own navigation lives.
    ///
    /// A PDF that carries an outline has one. Everything else has the thumbnail browser,
    /// which `comic-reader` calls for by name: "every page is shown in a scrollable strip
    /// with the current page marked".
    private func openContents() {
        if let pdfText, !pdfText.outline.isEmpty {
            findingTab = .contents
            isShowingMenu = false
            isFindingText = true
            return
        }
        isShowingMenu = false
        withAnimation(.easeInOut(duration: 0.2)) { isBrowsingThumbnails = true }
    }

    /// The position, in this reader's own units.
    ///
    /// Pages, because this reader only ever opens a publication whose pages are a stable
    /// identity — a reflowable EPUB is routed to the other reader, which states its position
    /// in words for the reason `ebook-reader` gives.
    var positionText: Text {
        Text("reader.page \(sliderIndex + 1) \(model.pages.count)", bundle: .module)
    }
}
