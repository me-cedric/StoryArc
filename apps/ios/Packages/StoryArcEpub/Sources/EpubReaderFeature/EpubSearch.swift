public import Foundation

internal import ReadiumNavigator
internal import ReadiumShared

public import StoryArcCore

// Searching inside the book.
//
// `ebook-reader`: "matches are listed with surrounding context and tapping one jumps to it".
// Readium walks the resources and reports a page of locators at a time, so results are
// published as they arrive rather than at the end -- a reader looking for a word they know is
// in chapter two should not wait for chapter forty.
//
// Android's `EpubReaderViewModel.search` does the same walk.

public extension EpubReaderModel {

    /// Searches the whole publication.
    ///
    /// A new search replaces the one before it. The field is searched as it is typed, and a
    /// previous query still filling the list would put its results under the new one's.
    func search(_ query: String) async {
        searchGeneration += 1
        let generation = searchGeneration

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            matches = []
            isSearching = false
            return
        }

        matches = []
        isSearching = true
        defer { if generation == searchGeneration { isSearching = false } }

        // Nil when the publication has no search service. The list then says nothing was
        // found, which is true, rather than reporting a failure a reader cannot act on.
        guard let iterator = await Self.iterator(of: opened, for: trimmed) else { return }

        var next = 0
        while let page = await Self.page(of: iterator) {
            // The reader typed again while this was walking. Its results belong to a query
            // that is no longer on screen.
            guard generation == searchGeneration else { return }
            guard !page.locators.isEmpty else { return }

            matches += page.locators.map { locator in
                defer { next += 1 }
                return SearchMatch(
                    id: next,
                    locator: (try? locator.jsonString()) ?? "",
                    chapter: locator.title ?? "",
                    snippet: SearchSnippet(
                        before: locator.text.before ?? "",
                        match: locator.text.highlight ?? "",
                        after: locator.text.after ?? ""
                    )
                )
            }
        }
    }

    /// Goes to a hit. The same journey a bookmark takes, from the same kind of record.
    func go(to match: SearchMatch) async {
        guard let navigator, let locator = try? Locator(jsonString: match.locator) else { return }
        _ = await navigator.go(to: locator, options: NavigatorGoOptions(animated: false))
    }

    /// `nonisolated` for the reason ``opened`` is: Readium's search walks resources off this
    /// actor, and its iterator is a plain class from a library written before strict
    /// concurrency.
    nonisolated private static func iterator(
        of publication: ReadiumShared.Publication?,
        for query: String
    ) async -> SearchIterator? {
        guard let publication else { return nil }
        return try? await publication.search(query: query).get()
    }

    nonisolated private static func page(of iterator: SearchIterator) async -> LocatorCollection? {
        // A double optional: the call can fail, and success can mean "no more pages".
        guard let page = try? await iterator.next().get() else { return nil }
        return page
    }
}
