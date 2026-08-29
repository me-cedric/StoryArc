public import Foundation

/// One hit from a search inside a publication.
///
/// Not persisted, unlike ``Bookmark``: a search is a question a reader asked once, and the
/// answer stops being true the moment they ask a different one. The locator is carried as the
/// renderer's own JSON for the reason a bookmark's is — it is the only thing that lands on
/// the same words after a type size has moved every page break.
///
/// Android's `SearchMatch` is the same record.
public struct SearchMatch: Sendable, Equatable, Identifiable {
    /// Position in the run of results. Two hits on one page share a locator, so the locator
    /// cannot be the identity — and a list keyed on a duplicate is a list that loses rows.
    public let id: Int
    public let locator: String
    /// The chapter it falls in, as the publication's own navigation names it.
    public let chapter: String
    /// The match and the words around it, bounded for a row.
    public let snippet: SearchSnippet

    public init(id: Int, locator: String, chapter: String, snippet: SearchSnippet) {
        self.id = id
        self.locator = locator
        self.chapter = chapter
        self.snippet = snippet
    }
}
