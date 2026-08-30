public import Foundation

internal import ReadiumNavigator
internal import ReadiumShared
internal import UIKit

public import StoryArcCore

// What a link inside the book does.
//
// `ebook-reader`: "a footnote opens in place as a popover, and a longer jump navigates with
// a control to return to where they were". Readium tells the two apart — it fetches a note's
// own markup and offers it through `shouldNavigateToNoteAt` — so this only has to decide
// what each one means here.
//
// Android's `EpubReaderActivity.shouldFollowInternalLink` makes the same two decisions.

public extension EpubReaderModel {

    /// Shows a footnote. The markup Readium reports, as the words in it.
    func showNote(_ markup: String) {
        note = Excerpt.plainText(markup).isEmpty ? nil : Excerpt.plainText(markup)
    }

    func dismissNote() {
        note = nil
    }

    /// Asks before the book sends the reader out of it.
    ///
    /// Two things happen here, and both matter. Anything that is not `http` or `https` is
    /// dropped: handed a `someapp://` URL the system launches whichever installed app claimed
    /// that scheme, with the parameters the publication chose, on one tap under link text the
    /// publication also chose. And what survives is *named* — a link is only honest if the
    /// reader can see where it goes before they go there.
    func askToLeave(for url: URL) {
        leaving = ExternalLink(url: url)
    }

    /// The reader said no, or dismissed the question.
    func stayInTheBook() {
        leaving = nil
    }

    /// The reader said yes. The address goes to the system exactly as the book wrote it.
    func leaveTheBook() {
        let going = leaving
        leaving = nil
        guard let going else { return }
        UIApplication.shared.open(going.url)
    }

    /// Remembers where the reader is, because they are about to not be there.
    func markReturnPoint() {
        returnPoint = locator.flatMap { try? $0.jsonString() }
    }

    /// Goes back, and puts the control away.
    ///
    /// The point is taken rather than kept: the control's whole promise is that it goes away
    /// once it has done what it offers, and a return that recorded where it returned *from*
    /// would leave a button that bounces the reader between two pages for ever.
    func returnToWhereTheyWere() async {
        guard let json = returnPoint else { return }
        returnPoint = nil
        guard let navigator, let locator = try? Locator(jsonString: json) else { return }
        _ = await navigator.go(to: locator, options: NavigatorGoOptions(animated: false))
    }
}
