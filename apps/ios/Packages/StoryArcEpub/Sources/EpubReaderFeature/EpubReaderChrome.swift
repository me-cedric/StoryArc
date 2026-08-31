internal import SwiftUI

internal import DesignSystem

// The reflowable reader's controls: a way out, a way in, and nothing else.
//
// `comic-reader`'s *Revealing controls* is written as a count — "exactly two controls fade
// in over the page … no title, page number, percentage or slider is drawn over the page" —
// and `ebook-reader` builds on the same two. It reads the same for a book as for a comic.
//
// **What used to be here.** Close, bookmark, contents, themes and read-aloud as five glass
// pills, a chapter-title chip, and a percentage at the bottom. Seven things, four of which
// were facts rather than actions. They are all still reachable, in `EpubReaderMenu.swift`,
// labelled in words.
//
// **What is deliberately still over the page, and why it is not a third control.** The
// return-to-position offer and the read-aloud transport are in `EpubReaderView`, not here.
// Neither is revealed by the centre tap: one is armed by a long jump the reader just made
// and disarmed by taking it, the other exists only while a voice is speaking. The count in
// the requirement is about what revealing the chrome puts on screen.
//
// `ReaderChromeTests` counts the buttons in this file. Two.
extension EpubReaderView {
    /// The controls. One tap away, and gone while reading.
    var chrome: some View {
        VStack {
            HStack {
                Button { dismiss() } label: {
                    Label {
                        Text("epub.close", bundle: .module)
                    } icon: {
                        Image(systemName: "xmark")
                    }
                    .labelStyle(.iconOnly)
                }
                // The platform's own glass button, rather than glass painted behind a plain
                // one: it carries the interactive highlight and the Reduce-Transparency
                // fallback that a hand-rolled pill would not.
                .buttonStyle(.glass)
                .tint(theme.palette.textPrimary)

                Spacer()

                Button { isShowingMenu = true } label: {
                    Label {
                        Text("epub.menu", bundle: .module)
                    } icon: {
                        Image(systemName: "ellipsis")
                    }
                    .labelStyle(.iconOnly)
                }
                .buttonStyle(.glass)
                .tint(theme.palette.textPrimary)
            }
            .padding(StoryArcSpace.md)

            Spacer()
        }
        .transition(.opacity)
    }
}
