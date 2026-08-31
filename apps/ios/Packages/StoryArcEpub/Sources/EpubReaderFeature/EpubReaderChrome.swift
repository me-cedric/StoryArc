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
                // The platform's own glass button, and **untinted**. `.tint` on a glass
                // button tints the *material*, not the glyph — which is why these
                // photographed as flat white pills with no page showing through them, and
                // why they did not look like the system's own floating controls.
                // `DesignSystem/Glass.swift` had already written the rule down: "Untinted,
                // deliberately: the spec wants the glass to pick up the page beneath it,
                // and a tint is precisely what stops it doing that", and "a fixed colour
                // cannot sit on this material" — found once before, on a device, and then
                // reintroduced here.
                //
                // The glyph takes a hierarchical style instead, which resolves against the
                // material rather than against a stored sRGB value, so it follows a page
                // that is cream under one theme and near-black under another.
                .buttonStyle(.glass)
                .foregroundStyle(.primary)
                // Large, which is the scale the system draws floating chrome at — the
                // controls in Photos' own overlay are half again the size of a toolbar
                // button, because a control floating over content has no bar to sit in and
                // has to carry its own presence. At the default size these read as small
                // pale dots on a page rather than as the platform's own chrome.
                .controlSize(.large)

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
                .foregroundStyle(.primary)
                .controlSize(.large)
            }
            .padding(StoryArcSpace.md)

            Spacer()
        }
        .transition(.opacity)
    }
}
