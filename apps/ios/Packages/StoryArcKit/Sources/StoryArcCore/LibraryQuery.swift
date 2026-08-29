public import Foundation

/// How far through a publication the reader got, as the library thinks of it.
public enum ReadState: String, Sendable, CaseIterable, Codable {
    case unread
    case inProgress
    case finished
}

/// What the library is ordered by.
///
/// `library-browsing` also lists date added and file size. Neither is recorded
/// yet — a scan does not write down when it first saw a file, and the archive
/// layer reports page sizes rather than a file size. They are absent rather than
/// present and wrong.
public enum LibrarySort: String, Sendable, CaseIterable, Codable {
    case title
    case series
    case lastRead
    case progress
    case year
}

/// The years a publication may have been released in.
///
/// `library-browsing` asks for a year *range* rather than a set of years, so this
/// is a pair of bounds and not another `Set`. Either end may be absent: "since
/// 1986" and "up to 1999" are both things a reader means, and requiring both would
/// make the filter harder to set than to ignore.
public struct YearRange: Sendable, Equatable, Codable {
    public var from: Int?
    public var to: Int?

    public init(from: Int? = nil, to: Int? = nil) {
        self.from = from
        self.to = to
    }

    /// Whether the range narrows anything. One bound is enough.
    public var isActive: Bool { from != nil || to != nil }

    /// Whether a publication's year falls inside.
    ///
    /// A publication with no year is **outside** an active range. It is not
    /// "before everything" — the library simply does not know when it came out,
    /// and answering a question about years with a book that has none would put
    /// noise in every result the filter is meant to remove.
    public func contains(_ year: Int?) -> Bool {
        guard isActive else { return true }
        guard let year else { return false }
        if let from, year < from { return false }
        if let to, year > to { return false }
        return true
    }
}

/// What the user is looking at, and in what order.
///
/// One value rather than a dozen pieces of view state, so "return to the library
/// and the filters are still applied" is one thing to keep and one thing to
/// restore.
///
/// Seven of the ten facets `library-browsing` names are here: read state, format,
/// language, publisher, genre, tag and year range. The other three are absent
/// rather than half-built, and the spec's own Open Questions say why — download
/// state needs the library to know what has been downloaded, source belongs to
/// the scope selector the same spec asks for, and no format this app reads states
/// a publication status at all.
public struct LibraryQuery: Sendable, Equatable, Codable {
    public var search: String
    public var readStates: Set<ReadState>
    public var formats: Set<PublicationFormat>
    public var languages: Set<String>
    /// Publishers, as the publication spells them. Not normalised: "DC" and "DC
    /// Comics" are two publishers to a file and pretending otherwise would drop
    /// books out of a filter the reader set.
    public var publishers: Set<String>
    public var genres: Set<String>
    public var tags: Set<String>
    public var years: YearRange
    public var sort: LibrarySort
    public var ascending: Bool

    public init(
        search: String = "",
        readStates: Set<ReadState> = [],
        formats: Set<PublicationFormat> = [],
        languages: Set<String> = [],
        publishers: Set<String> = [],
        genres: Set<String> = [],
        tags: Set<String> = [],
        years: YearRange = YearRange(),
        sort: LibrarySort = .title,
        ascending: Bool = true
    ) {
        self.search = search
        self.readStates = readStates
        self.formats = formats
        self.languages = languages
        self.publishers = publishers
        self.genres = genres
        self.tags = tags
        self.years = years
        self.sort = sort
        self.ascending = ascending
    }

    /// What the filter control shows as a badge.
    ///
    /// A group counts once however many values it holds: three formats is one
    /// decision the user made, and a badge reading "5" for it would misdescribe
    /// how much has to be undone. The year range is one group whichever of its two
    /// ends the reader set, for the same reason.
    public var activeFilterCount: Int {
        [
            !readStates.isEmpty,
            !formats.isEmpty,
            !languages.isEmpty,
            !publishers.isEmpty,
            !genres.isEmpty,
            !tags.isEmpty,
            years.isActive,
        ].count { $0 }
    }

    public var hasFilters: Bool { activeFilterCount > 0 }

    /// Whether anything at all is narrowing the view, search included.
    public var isNarrowed: Bool {
        hasFilters || !search.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Every filter off, the search and the sort untouched.
    ///
    /// `library-browsing`: an empty-looking library must say filters are active and
    /// offer one action to clear them. Here rather than in the view model so the
    /// two platforms clear the same set — a facet added to one and forgotten in the
    /// other's clear-all is exactly the drift ADR-0001 makes us watch for.
    public var withoutFilters: LibraryQuery {
        var cleared = self
        cleared.readStates = []
        cleared.formats = []
        cleared.languages = []
        cleared.publishers = []
        cleared.genres = []
        cleared.tags = []
        cleared.years = YearRange()
        return cleared
    }

    /// Decoded field by field, every one of them optional.
    ///
    /// The synthesized decoder requires every key to be present, and a query
    /// written by an earlier build has none of the facets added since. That
    /// decoder throws, `LibraryPreferences` falls back to a fresh query, and the
    /// reader's filters silently disappear on the launch after an update — which
    /// is the one thing "active filters are still applied" forbids. So each field
    /// falls back to its default instead.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        search = try container.decodeIfPresent(String.self, forKey: .search) ?? ""
        readStates = try container.decodeIfPresent(Set<ReadState>.self, forKey: .readStates) ?? []
        formats = try container.decodeIfPresent(Set<PublicationFormat>.self, forKey: .formats) ?? []
        languages = try container.decodeIfPresent(Set<String>.self, forKey: .languages) ?? []
        publishers = try container.decodeIfPresent(Set<String>.self, forKey: .publishers) ?? []
        genres = try container.decodeIfPresent(Set<String>.self, forKey: .genres) ?? []
        tags = try container.decodeIfPresent(Set<String>.self, forKey: .tags) ?? []
        years = try container.decodeIfPresent(YearRange.self, forKey: .years) ?? YearRange()
        sort = try container.decodeIfPresent(LibrarySort.self, forKey: .sort) ?? .title
        ascending = try container.decodeIfPresent(Bool.self, forKey: .ascending) ?? true
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
