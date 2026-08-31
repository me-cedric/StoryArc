public import Foundation

internal import ReadiumNavigator
internal import ReadiumShared

public import Persistence
public import StoryArcCore

// The places a reader marked, and the reading of them back out of the book.
//
// `ebook-reader`: a bookmark "is saved with its chapter title and a text excerpt, and is
// listed alongside the table of contents". The record and its store are shared with the
// library; what is here is the half only a reader can do — knowing where the reader is,
// and finding the words there.
//
// Android's `EpubReaderViewModel` carries the same four operations.

public extension EpubReaderModel {

    /// The mark already on this page, if there is one.
    ///
    /// What makes the control a toggle rather than a button that only ever adds.
    var isPageBookmarked: Bool { markHere != nil }

    private var markHere: Bookmark? {
        guard let locator else { return nil }
        return bookmarks.mark(
            at: totalProgression(of: locator),
            in: locator.href.removingFragment().string
        )
    }

    /// Marks this page, or unmarks it.
    ///
    /// Removing needs nothing read, so it does not wait on a resource. Adding does: the
    /// control answers immediately and the excerpt catches up, because a bookmark button
    /// that waited for a disk read before changing colour would feel broken on the one
    /// press a reader is most sure about.
    func toggleBookmark() async {
        guard let store = bookmarkStore, let locator else { return }

        if let existing = markHere {
            bookmarks = store.remove(existing.id, from: publication.id)
            return
        }

        let excerpt = await excerpt(at: locator)
        bookmarks = store.toggle(
            Bookmark(
                locator: (try? locator.jsonString()) ?? "",
                resource: locator.href.removingFragment().string,
                progression: totalProgression(of: locator),
                chapter: locator.title ?? "",
                excerpt: excerpt,
                createdAt: Date()
            ),
            in: publication.id
        )
    }

    /// Forgets one mark, which is what its row in the list offers.
    func removeBookmark(_ id: UUID) {
        guard let store = bookmarkStore else { return }
        bookmarks = store.remove(id, from: publication.id)
    }

    /// Goes back to a mark.
    ///
    /// The stored locator rather than a position derived from it: a bookmark records where
    /// Readium said the reader was, and handing that back is the only way to land on the
    /// same words after a type size has moved every page break.
    func go(to bookmark: Bookmark) async {
        guard let navigator,
              let locator = try? Locator(jsonString: bookmark.locator)
        else { return }
        markReturnPoint()
        _ = await navigator.go(to: locator, options: NavigatorGoOptions(animated: false))
    }

    /// A little of the text where the reader is.
    ///
    /// What Readium reports is preferred; the resource is read only when it reports
    /// nothing, which is the usual case because a locator from a page turn carries no text.
    /// A resource that cannot be read gives an empty excerpt and a row that names its
    /// chapter alone, which is still more than a percentage would say.
    /// One resource, as text.
    ///
    /// `nonisolated` so the read happens off the main actor, which is where a disk read
    /// belongs -- Android's half puts the same read on `Dispatchers.IO`.
    ///
    /// Not private: the theme sheet's live preview reads the same resource the same way,
    /// and `reading-themes` asks it to use "text from the open publication where one is
    /// open". Two copies of one `readAsString` is one copy too many.
    nonisolated internal static func markup(
        of publication: ReadiumShared.Publication?,
        at href: AnyURL
    ) async -> String? {
        guard let publication else { return nil }
        return try? await publication.get(href)?.readAsString().get()
    }

    private func excerpt(at locator: Locator) async -> String {
        if let highlight = locator.text.highlight?.trimmingCharacters(in: .whitespacesAndNewlines),
           !highlight.isEmpty {
            return highlight
        }
        guard let markup = await Self.markup(of: opened, at: locator.href.removingFragment())
        else { return "" }
        return Excerpt.at(
            Excerpt.plainText(markup),
            fraction: locator.locations.progression ?? 0
        )
    }
}
