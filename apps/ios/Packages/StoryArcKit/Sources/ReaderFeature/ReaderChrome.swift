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
                // The platform's own glass button rather than glass painted behind a plain
                // one: it carries the interactive highlight and its own
                // Reduce-Transparency fallback, which a hand-rolled pill does not.
                .buttonStyle(.glass)
                .tint(.white)

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
                .tint(.white)
            }
            .padding(StoryArcSpace.md)

            Spacer()
        }
        .transition(.opacity)
    }
}
