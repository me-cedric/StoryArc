internal import Foundation

public import StoryArcCore

/// What the filter control offers, and how it is turned off.
///
/// Split out of ``LibraryModel`` because that file was within thirty lines of the
/// 400-line cap, and this is a seam that was already there: everything here
/// answers "what can the reader narrow the library by", and every value comes from
/// the publications the library actually holds. A filter that offers a value no
/// publication carries would empty the shelf the moment it was ticked, which is
/// only avoidable from the library itself.
extension LibraryModel {
    /// Clears every filter, keeping the search and the sort.
    ///
    /// `library-browsing`: an empty-looking library must say filters are active
    /// and offer one action to clear them. This is that action. Which groups it
    /// clears lives on the query itself, so a facet added to the query cannot be
    /// forgotten here.
    public func clearFilters() {
        query = query.withoutFilters
    }

    /// Formats actually present, so the filter never offers one that would empty
    /// the library.
    public var availableFormats: [PublicationFormat] {
        Array(Set(publications.map(\.format))).sorted { $0.displayName < $1.displayName }
    }

    /// Languages actually present, as codes. The view names them for the reader —
    /// the model has no business holding "Français".
    public var availableLanguages: [String] {
        Array(Set(publications.compactMap(\.language))).sorted()
    }

    /// Publishers actually present, as the files spell them.
    public var availablePublishers: [String] {
        Array(Set(publications.compactMap(\.publisher))).sorted()
    }

    /// Genres actually present, gathered from every publication's list.
    public var availableGenres: [String] {
        Array(Set(publications.flatMap(\.genres))).sorted()
    }

    /// Tags actually present. Kept apart from ``availableGenres`` because the
    /// files keep them apart.
    public var availableTags: [String] {
        Array(Set(publications.flatMap(\.tags))).sorted()
    }

    /// The decades the library spans, newest first.
    ///
    /// `library-browsing` asks for a year *range*, and ``LibraryQuery/years``
    /// carries an arbitrary one — which is what the tests assert and what a future
    /// control will set. What the menu offers is decades, because a menu cannot ask
    /// for two numbers without becoming a form, and a decade is a range a reader
    /// picks in one tap. Derived from the years actually present, so the filter
    /// never offers a decade the library has nothing in.
    public var availableDecades: [Int] {
        Array(Set(publications.compactMap(\.year).map { $0 - $0 % 10 })).sorted(by: >)
    }
}
