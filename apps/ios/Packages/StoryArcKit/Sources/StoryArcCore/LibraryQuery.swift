public import Foundation

/// How far through a publication the reader got, as the library thinks of it.
public enum ReadState: String, Sendable, CaseIterable, Codable {
    case unread
    case inProgress
    case finished
}

/// What the library is ordered by.
///
/// The seven fields `library-browsing` names. Date added and file size come last
/// because they arrived last: adding them at the end leaves every earlier case
/// where a reader's stored preference already points, and the raw values are the
/// names rather than the positions anyway.
public enum LibrarySort: String, Sendable, CaseIterable, Codable {
    case title
    case series
    case lastRead
    case progress
    case year
    case dateAdded
    case fileSize
}

/// What the user is looking at, and in what order.
///
/// One value rather than five pieces of view state, so "return to the library and
/// the filters are still applied" is one thing to keep and one thing to restore.
public struct LibraryQuery: Sendable, Equatable, Codable {
    public var search: String
    public var readStates: Set<ReadState>
    public var formats: Set<PublicationFormat>
    public var languages: Set<String>
    public var sort: LibrarySort
    public var ascending: Bool

    public init(
        search: String = "",
        readStates: Set<ReadState> = [],
        formats: Set<PublicationFormat> = [],
        languages: Set<String> = [],
        sort: LibrarySort = .title,
        ascending: Bool = true
    ) {
        self.search = search
        self.readStates = readStates
        self.formats = formats
        self.languages = languages
        self.sort = sort
        self.ascending = ascending
    }

    /// What the filter control shows as a badge.
    ///
    /// A group counts once however many values it holds: three formats is one
    /// decision the user made, and a badge reading "5" for it would misdescribe
    /// how much has to be undone.
    public var activeFilterCount: Int {
        [!readStates.isEmpty, !formats.isEmpty, !languages.isEmpty].count { $0 }
    }

    public var hasFilters: Bool { activeFilterCount > 0 }

    /// Whether anything at all is narrowing the view, search included.
    public var isNarrowed: Bool {
        hasFilters || !search.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

/// How publications are drawn.
///
/// `library-browsing` requires both: a cover grid, and a compact list for a
/// library too large to recognise by artwork alone.
public enum LibraryLayout: String, Sendable, CaseIterable, Codable {
    case grid
    case list
}

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

        let kept = publications.filter { publication in
            let record = progress(publication)
            return (query.readStates.isEmpty || query.readStates.contains(record.state))
                && (query.formats.isEmpty || query.formats.contains(publication.format))
                && (query.languages.isEmpty || publication.language.map(query.languages.contains) == true)
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

    /// An issue number as a number, so #10 follows #9.
    ///
    /// A publication with no number sorts last, which keeps a one-off out of the
    /// middle of a numbered run.
    private static func issueNumber(of publication: Publication) -> Double {
        guard let raw = publication.number else { return .greatestFiniteMagnitude }
        return Double(raw.filter { $0.isNumber || $0 == "." }) ?? .greatestFiniteMagnitude
    }

    /// How well a publication answers the query, lower being better, or `nil` for
    /// no match at all.
    ///
    /// A title that starts with what was typed is what the user meant far more
    /// often than an author whose name contains it somewhere.
    private static func rank(_ publication: Publication, matching term: String) -> Int? {
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
            let bySeries = collate(left.series ?? left.displayTitle, right.series ?? right.displayTitle, locale)
            if bySeries != .orderedSame { return bySeries }
            // Within a series, the issue number decides — and numerically, so #10
            // follows #9 rather than #1.
            return order(number(of: left), number(of: right))

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

    private static func order<T: Comparable>(_ left: T, _ right: T) -> ComparisonResult {
        if left < right { return .orderedAscending }
        if left > right { return .orderedDescending }
        return .orderedSame
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
