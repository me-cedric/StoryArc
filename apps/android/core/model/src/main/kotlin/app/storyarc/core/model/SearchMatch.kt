package app.storyarc.core.model

/**
 * One hit from a search inside a publication.
 *
 * Not persisted, unlike [Bookmark]: a search is a question a reader asked once, and the
 * answer stops being true the moment they ask a different one. The locator is carried as the
 * renderer's own JSON for the reason a bookmark's is -- it is the only thing that lands on
 * the same words after a type size has moved every page break.
 *
 * iOS's `SearchMatch` is the same record.
 */
data class SearchMatch(
    val locator: String,
    /** The chapter it falls in, as the publication's own navigation names it. */
    val chapter: String,
    /** The match and the words around it, bounded for a row. */
    val snippet: SearchSnippet,
)
