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
                    // The quieter half of the row, and still on a material the page tints —
                    // `storyArcGlassText` rather than a bare `.secondary` so it takes the
                    // palette's neutral back under Reduce Transparency, where the sheet's
                    // ground becomes `surfaceOverlay` and is knowable again.
                    .storyArcGlassText(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .leading) { coarseFill }
        }
        // PB-open: this row sits first in the sheet's `List`, directly under the grabber —
        // the one spot `.presentationDetents([.medium, .large])` also wants a touch for, to
        // drag the sheet between its two heights. Without a competing recognizer here, that
        // drag gesture sometimes wins the arena for a plain tap that never leaves this row,
        // and the `Button`'s own action never runs: `SweepComicReaderTests
        // .testCaptureComicPageBrowser` failed "Contents opened no page browser" on every
        // run, on a booted simulator, with no error from the tap itself — the touch landed,
        // nothing read it. A `simultaneousGesture` tap recognizer asks to recognize
        // alongside the drag rather than lose to it, so the row opens on the first tap.
        .simultaneousGesture(TapGesture().onEnded { openContents() })
        // One element, spoken once. The position is a second line of this row rather than a
        // separate thing to swipe to, and `comic-reader` is explicit that "the text is what
        // conveys the position".
        .accessibilityElement(children: .combine)
    }

    /// The coarse position, drawn behind the row.
    ///
    /// `comic-reader`, *Where the reader is, at a glance*: "the coarse position through the
    /// publication is drawn as a fill behind the menu's own contents row, and stated in text
    /// on that row … the text is what conveys the position, so the fill may be absent without
    /// anything being lost — it is not the only indication."
    ///
    /// A `Rectangle` in a `GeometryReader` rather than a `ProgressView`: the fill has to be
    /// the row's own background at the row's own height, and a progress view brings a track,
    /// a corner radius and a minimum height that none of that wants.
    ///
    /// **Decorative to assistive technology, and that is the load-bearing part.** The text
    /// beside it already states the position. A page number announced twice is a page number
    /// announced wrong, so this is hidden rather than labelled — and the row above combines
    /// its children into one element, which is what keeps the two from being read separately.
    var coarseFill: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(theme.accent.opacity(0.14))
                .frame(width: geometry.size.width * fraction)
        }
        .accessibilityHidden(true)
    }

    /// The fill's width as a fraction of the row, clamped to the row.
    ///
    /// Pages, because this reader only ever opens a publication whose pages are a stable
    /// identity. A one-page publication is all the way through it.
    var fraction: CGFloat {
        guard model.pages.count > 1 else { return 1 }
        let position = CGFloat(sliderIndex) / CGFloat(model.pages.count - 1)
        return min(max(position, 0), 1)
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
        // `page-browser-carousel`: the carousel and the page slider drive each other, so
        // they share one sheet now — the menu stays open rather than handing off to a
        // sheet of its own. Seeded from the reader's own page, the only position a
        // carousel opened on a different one would have to swipe away from.
        //
        // An assignment, not `.toggle()`. This row now carries two routes to this method —
        // the `Button`'s own action and the `simultaneousGesture` above — so a tap that
        // both recognizers accept calls this twice. `.toggle()` would make a double call
        // net back to `false`; an assignment leaves the browser open either way.
        centredPreviewIndex = model.currentIndex
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
