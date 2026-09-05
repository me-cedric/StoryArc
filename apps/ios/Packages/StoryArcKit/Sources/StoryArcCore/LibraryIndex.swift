public import Foundation

/// Turns the whole library into the list on screen.
///
/// Pure, and deliberately so: this is the part of `library-browsing` that has to
/// behave identically on both platforms, and it is the part worth asserting
/// against the same table in both test suites (ADR-0001). Android's
/// `LibraryIndex` mirrors it line for line.
///
/// Not here yet, and named rather than silently missing: grouping results by
/// match kind, merging a server's own search with local results, and the curated
/// order of a reading list. All three need a second source or a collection to
/// exist.
public enum LibraryIndex {

    /// What the library knows about a publication's progress.
    public struct Progress: Sendable, Equatable {
        public let state: ReadState
        public let fraction: Double
        public let lastReadAt: Date?

        public init(state: ReadState, fraction: Double, lastReadAt: Date?) {
            self.state = state
            self.fraction = fraction
            self.lastReadAt = lastReadAt
        }

        public static let unread = Progress(state: .unread, fraction: 0, lastReadAt: nil)

        public static func of(_ record: ReadingProgress?) -> Progress {
            guard let record else { return .unread }
            let fraction = record.isFinished ? 1 : record.position.fraction
            let state: ReadState =
                if record.isFinished { .finished } else if fraction > 0 { .inProgress } else { .unread }
            return Progress(state: state, fraction: fraction, lastReadAt: record.updatedAt)
        }
    }

    /// The filtered, ranked and sorted list.
    ///
    /// Ranking only applies while a search is running: with a query, how well a
    /// publication matches is more useful than the sort field, and the sort
    /// breaks ties within each rank.
    public static func arrange(
        _ publications: [Publication],
        query: LibraryQuery,
        locale: Locale = .current,
        progress: (Publication) -> Progress = { _ in .unread }
    ) -> [Publication] {
        let term = query.search.trimmingCharacters(in: .whitespaces).lowercased()

        // Narrowed to the by-library filter **only while nothing is being searched for**.
        //
        // This used to narrow unconditionally, quoting `library-browsing`'s old *Scoping to
        // one source*: "the view, its search, and its filters apply to that source alone".
        // `one-library-three-destinations` replaced that sentence. Narrowing to one library
        // is a filter now rather than a scope the view is in, and the requirement says what
        // it may reach: it "narrows what the shelf lists and nothing else — **search still
        // covers the whole library**".
        //
        // So the filter applies to the listing and stands down for a query. That is what
        // makes search a destination rather than a view of the shelf: a reader who narrowed
        // the shelf to one library yesterday and searches for a title today is asking the
        // library a question, not asking that one library. ``grouped(_:query:locale:progress:)``
        // inherits this by deriving from here, which is why the rule lives in one place.
        let searchable = term.isEmpty ? inScope(publications, query.scope) : publications
        let kept = searchable.filter { publication in
            keeps(publication, query: query, state: progress(publication).state)
                && (term.isEmpty || rank(publication, matching: term) != nil)
        }

        return kept.sorted { left, right in
            if !term.isEmpty {
                let leftRank = rank(left, matching: term) ?? .max
                let rightRank = rank(right, matching: term) ?? .max
                if leftRank != rightRank { return leftRank < rightRank }
            }
            let byField = compare(left, right, by: query.sort, locale: locale, progress: progress)
            if byField != .orderedSame {
                return query.ascending ? byField == .orderedAscending : byField == .orderedDescending
            }
            // A stable tiebreak, always ascending: a list that reshuffles equal
            // rows when the direction flips looks broken.
            return collate(left.displayTitle, right.displayTitle, locale) == .orderedAscending
        }
    }

    /// In-progress publications, most recently read first.
    ///
    /// `library-browsing`: the continue row "is absent, rather than shown empty,
    /// when nothing is in progress" — so this returns an empty array and the
    /// caller draws nothing, rather than a header over a gap.
    public static func continueReading(
        _ publications: [Publication],
        limit: Int = 12,
        progress: (Publication) -> Progress
    ) -> [Publication] {
        publications
            .compactMap { publication -> (Publication, Progress)? in
                let record = progress(publication)
                return record.state == .inProgress ? (publication, record) : nil
            }
            .sorted { ($0.1.lastReadAt ?? .distantPast) > ($1.1.lastReadAt ?? .distantPast) }
            .prefix(limit)
            .map(\.0)
    }

    /// The next publication in the same series.
    ///
    /// `comic-reader`: reaching the end of one volume offers the next. Matching is
    /// on the series name and the issue number, which is all a local library knows
    /// — a reading list carries its own order and will answer this differently when
    /// there are reading lists.
    ///
    /// `nil` when the publication names no series, when nothing follows it, or when
    /// the next thing cannot be opened. Offering a publication that refuses to open
    /// would be worse than offering nothing.
    public static func next(after publication: Publication, in library: [Publication]) -> Publication? {
        guard let series = publication.series else { return nil }
        let current = issueNumber(of: publication)

        return library
            .filter { candidate in
                candidate.id != publication.id
                    && candidate.series == series
                    && candidate.isOpenable
                    && issueNumber(of: candidate) > current
            }
            .min { issueNumber(of: $0) < issueNumber(of: $1) }
    }

    /// The publication before this one in the same series.
    ///
    /// `comic-reader`: "the reader offers previous and next chapter actions without
    /// returning to the library". The mirror of ``next(after:in:)`` and deliberately
    /// written the same way — a series is ordered by issue number, so going back is
    /// the same query with the comparison and the tie-break reversed.
    ///
    /// `nil` when the publication names no series, when nothing precedes it, or when
    /// what precedes it cannot be opened.
    public static func previous(before publication: Publication, in library: [Publication]) -> Publication? {
        guard let series = publication.series else { return nil }
        let current = issueNumber(of: publication)

        return library
            .filter { candidate in
                candidate.id != publication.id
                    && candidate.series == series
                    && candidate.isOpenable
                    && issueNumber(of: candidate) < current
            }
            .max { issueNumber(of: $0) < issueNumber(of: $1) }
    }

    /// An issue number as a number, so #10 follows #9.
    ///
    /// A publication with no number sorts last, which keeps a one-off out of the
    /// middle of a numbered run.
    private static func issueNumber(of publication: Publication) -> Double {
        guard let raw = publication.number else { return .greatestFiniteMagnitude }
        return Double(raw.filter { $0.isNumber || $0 == "." }) ?? .greatestFiniteMagnitude
    }

    /// Whether a publication survives every filter group.
    ///
    /// `library-browsing`: the groups "combine with AND", so an empty group is no
    /// opinion at all and any group holding values has to be satisfied. Within one
    /// group the values are alternatives — two formats ticked means either.
    ///
    /// Its own function rather than a chain inside ``arrange(_:query:locale:progress:)``:
    /// the chain is seven groups long now, and Android's `LibraryIndex.keeps` has
    /// to be readable against it line for line (ADR-0001).
    static func keeps(_ publication: Publication, query: LibraryQuery, state: ReadState) -> Bool {
        /// A group over a value the publication has at most one of.
        func holds(_ chosen: Set<String>, _ value: String?) -> Bool {
            chosen.isEmpty || value.map(chosen.contains) == true
        }
        /// A group over a value the publication can carry several of.
        func meets(_ chosen: Set<String>, _ values: [String]) -> Bool {
            chosen.isEmpty || values.contains(where: chosen.contains)
        }
        return (query.readStates.isEmpty || query.readStates.contains(state))
            && (query.formats.isEmpty || query.formats.contains(publication.format))
            && holds(query.languages, publication.language)
            && holds(query.publishers, publication.publisher)
            && meets(query.genres, publication.genres)
            && meets(query.tags, publication.tags)
            && query.years.contains(publication.year)
    }

    /// How well a publication answers the query, lower being better, or `nil` for
    /// no match at all.
    ///
    /// A title that starts with what was typed is what the user meant far more
    /// often than an author whose name contains it somewhere.
    /// Not `private`: `LibraryMatch` groups results by *why* they matched and asks this
    /// for the reason, and Swift's `private` is file-scoped.
    static func rank(_ publication: Publication, matching term: String) -> Int? {
        func has(_ value: String?) -> Bool { value?.lowercased().contains(term) == true }
        let title = publication.displayTitle.lowercased()
        if title.hasPrefix(term) { return 0 }
        if title.contains(term) { return 1 }
        if has(publication.series) { return 2 }
        if publication.authors.contains(where: { has($0) }) { return 3 }
        if has(publication.publisher) { return 4 }
        return nil
    }

    private static func compare(
        _ left: Publication,
        _ right: Publication,
        by sort: LibrarySort,
        locale: Locale,
        progress: (Publication) -> Progress
    ) -> ComparisonResult {
        switch sort {
        case .title:
            return collate(left.displayTitle, right.displayTitle, locale)

        case .series:
            return compareBySeries(left, right, locale)

        // Never read sorts last whichever way the list runs: a row with no date is
        // not "the oldest", it is absent from the ordering the user asked for.
        case .lastRead:
            let leftDate = progress(left).lastReadAt ?? .distantPast
            let rightDate = progress(right).lastReadAt ?? .distantPast
            return order(rightDate, leftDate)

        case .progress:
            return order(progress(right).fraction, progress(left).fraction)

        case .year:
            return order(right.year ?? 0, left.year ?? 0)

        // Newest first, the same way as `year` and `lastRead`: for a date, the
        // interesting end of the list is the recent one, and a reader asking for
        // what they added lately does not want 2019 at the top.
        case .dateAdded:
            let leftDate = left.addedAt ?? .distantPast
            let rightDate = right.addedAt ?? .distantPast
            return order(rightDate, leftDate)

        // Largest first, for the same reason `progress` puts the most-read first:
        // the reason to sort by size is to find what is taking up the disk.
        case .fileSize:
            return order(right.fileSize ?? 0, left.fileSize ?? 0)
        }
    }

    /// The series shelf: every series first in name order, then everything that names none.
    ///
    /// A publication that names no series belongs *after* every publication that names one,
    /// not among the series names its own title happens to fall between. Ordering it among
    /// them is what cut the standalone pile in two — "Zephyr" landing between "Ashfall" and
    /// "Blackwater" makes *Other* two piles rather than one, and a sectioned shelf that
    /// refuses to draw one heading twice then declines to divide the shelf at all.
    ///
    /// Its own function rather than a branch inside ``compare(_:_:by:locale:progress:)``:
    /// it is the only sort key with an absent case that is a pile of its own, and Android's
    /// `LibraryIndex` has the same block to be read against (ADR-0001).
    private static func compareBySeries(
        _ left: Publication,
        _ right: Publication,
        _ locale: Locale
    ) -> ComparisonResult {
        let leftSeries = seriesName(of: left)
        let rightSeries = seriesName(of: right)
        // One pile, alphabetical inside it, and reversing with the sort direction like every
        // other key so the pile stays a single contiguous run either way the shelf runs.
        if leftSeries == nil && rightSeries == nil {
            return collate(left.displayTitle, right.displayTitle, locale)
        }
        guard let leftSeries else { return .orderedDescending }
        guard let rightSeries else { return .orderedAscending }
        let bySeries = collate(leftSeries, rightSeries, locale)
        if bySeries != .orderedSame { return bySeries }
        // Within a series, the issue number decides — and numerically, so #10 follows #9
        // rather than #1.
        return order(number(of: left), number(of: right))
    }

    private static func order<T: Comparable>(_ left: T, _ right: T) -> ComparisonResult {
        if left < right { return .orderedAscending }
        if left > right { return .orderedDescending }
        return .orderedSame
    }

    /// The series a publication actually names, or `nil` when it names none.
    ///
    /// `nil`, `""` and `"   "` are one answer, not three. A real `ComicInfo.xml` writes all
    /// three for a book that belongs to no series, and a rule that told them apart would
    /// file identical shelves in different places.
    ///
    /// Public because the sectioned shelf has to divide on the same answer this sorts on:
    /// were the two to disagree about a blank name, a heading would open where the order
    /// never changed.
    public static func seriesName(of publication: Publication) -> String? {
        guard let trimmed = publication.series?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }

    private static func number(of publication: Publication) -> Double {
        guard let raw = publication.number else { return .greatestFiniteMagnitude }
        let digits = raw.filter { $0.isNumber || $0 == "." }
        return Double(digits) ?? .greatestFiniteMagnitude
    }

    private static func collate(_ left: String, _ right: String, _ locale: Locale) -> ComparisonResult {
        sortKey(left, locale: locale).compare(
            sortKey(right, locale: locale),
            options: [.caseInsensitive],
            range: nil,
            locale: locale
        )
    }

    /// A title as it should be alphabetised.
    ///
    /// `library-browsing` requires leading articles in the interface language to
    /// be ignored, so "The Sandman" files under S. The list is per language
    /// because "la" is an article in French and Spanish and a syllable in English,
    /// and stripping it from an English title would file "La Brea" under B.
    public static func sortKey(_ title: String, locale: Locale = .current) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        let articles = Self.articles[locale.language.languageCode?.identifier ?? ""] ?? []
        for article in articles {
            // The apostrophe forms — French "l'" — carry no space after them.
            let prefix = article.hasSuffix("'") ? article : article + " "
            if trimmed.count > prefix.count,
               trimmed.lowercased().hasPrefix(prefix) {
                return String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return trimmed
    }

    /// The four interface languages StoryArc ships.
    private static let articles: [String: [String]] = [
        "en": ["the", "a", "an"],
        "fr": ["le", "la", "les", "un", "une", "des", "l'"],
        "de": ["der", "die", "das", "ein", "eine"],
        "es": ["el", "la", "los", "las", "un", "una"],
    ]
}
