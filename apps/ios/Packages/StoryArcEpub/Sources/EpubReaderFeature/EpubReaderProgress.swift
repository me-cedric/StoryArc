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
// ``ReadingPositionLine`` decides what the line says; this file decides how it reads.
//
// The members are internal rather than private because `EpubReaderMenu` is in another file.
extension EpubReaderView {

    /// Where the reader is, as the shared rule sees it.
    var position: ReadingPositionLine {
        ReadingPositionLine.of(
            totalProgression: model.progression,
            chapter: model.chapterTitle,
            withinChapter: model.withinChapter
        )
    }

    /// The contents row: the position, in words, and the way to somewhere else.
    ///
    /// `comic-reader`, *Where the reader is, at a glance*: "the coarse position through the
    /// publication is drawn as a fill behind the menu's own contents row, and stated in text
    /// on that row … the text is what conveys the position, so the fill may be absent without
    /// anything being lost — it is not the only indication."
    var progressRow: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
            Label {
                Text(LocalizedStringKey(ReaderMenuEntry.contents.titleKey), bundle: .module)
            } icon: {
                Image(systemName: ReaderMenuEntry.contents.systemImage)
            }
            progressText
                .textRole(.caption)
                // **A fixed palette colour cannot sit here**, which is the finding
                // `DesignSystem/Glass.swift` records from a booted device and the reason
                // ``storyArcGlassText(_:)`` exists. This line sits on the menu's material,
                // and that material picks up the page: `textSecondary` is a constant and the
                // ground under it is not. See ``ReaderMenuOnGlassTests``.
                .storyArcGlassText(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .leading) { coarseFill }
    }

    /// The coarse position, drawn behind the row.
    ///
    /// A `Rectangle` in a `GeometryReader` rather than a `ProgressView`: the fill has to be
    /// the row's own background at the row's own height, and a progress view brings a track,
    /// a corner radius and a minimum height that none of that wants.
    ///
    /// **Decorative to assistive technology, and that is the load-bearing part.** The text
    /// above already states the position, and `comic-reader` is explicit that "the text is
    /// what conveys the position". A percentage announced twice is a percentage announced
    /// wrong, so this is hidden rather than labelled.
    var coarseFill: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(theme.accent.opacity(0.14))
                .frame(width: geometry.size.width * fraction)
        }
        .accessibilityHidden(true)
    }

    /// The fill's width as a fraction of the row, clamped to the row.
    var fraction: CGFloat { min(max(CGFloat(model.progression), 0), 1) }

    /// The position, as a sentence.
    ///
    /// A percentage, never a page number: `ebook-reader` is explicit that a reflowable page
    /// count is a function of the type size and must not be presented as an identity. The
    /// chapter half is a band in words rather than a second percentage — see
    /// ``ChapterRemainder``.
    ///
    /// Three localised fragments joined by punctuation rather than one key with three
    /// arguments, because the chapter's own title is the publication's and must not be
    /// translated, and the band's phrase is shared with Android's own `strings.xml`. Each
    /// fragment is translated on its own; the separators are punctuation.
    var progressText: Text {
        let through = Text("epub.progress \(position.percentThrough)", bundle: .module)
        guard let chapter = position.chapter else { return through }
        let named = through + Text(verbatim: " · ") + Text(verbatim: chapter)
        guard let remainder = position.chapterRemainder else { return named }
        return named + Text(verbatim: ", ")
            + Text(LocalizedStringKey(remainder.titleKey), bundle: .module)
    }
}
