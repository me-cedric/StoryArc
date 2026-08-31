internal import SwiftUI

internal import DesignSystem

// The reader's controls: a way out, a way in, and nothing else.
//
// `comic-reader`, *Revealing controls*: "exactly two controls fade in over the page — one
// that closes the publication and one that opens the reader's menu … no title, page
// number, percentage or slider is drawn over the page, because each of those is a fact the
// menu states better and none of them is an action."
//
// **What used to be here.** A top bar, a bottom bar and a page slider, and between them
// eleven controls: close, adjust, spread offset, PDF find, thumbnails, transition,
// direction, orientation lock, fit, chapter previous and next, plus a page counter and a
// skipped-pages notice. Every one was justified on its own. Together they took about a
// fifth of a phone screen and were the first thing a reader saw after the page. They are
// all still reachable — in `ReaderMenu.swift`, one tap away, labelled in words rather than
// left to be recognised from an icon.
//
// `ReaderChromeTests` counts the buttons in this file. Two. Adding a third here is the
// regression the count exists to stop, and the menu is where the third one goes.
//
// The members are internal rather than private because `ReaderView.body` is in the other
// file, and a `private` member of an extension cannot be reached from it.
extension ReaderView {
    /// The controls. One gesture away, and gone while reading.
    var chrome: some View {
        VStack {
            HStack {
                Button { dismiss() } label: {
                    Label {
                        Text("reader.close", bundle: .module)
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
                        Text("reader.menu", bundle: .module)
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
