public import Foundation

/// Why a publication answered a search.
///
/// `library-browsing`: search results "are grouped by match kind — series, publication,
/// person, tag". The kind is the answer to "why is this here", and a reader who typed a
/// word that is both an author's name and half a title needs that answer to make sense of
/// forty rows.
///
/// Android's `MatchKind` mirrors it.
public enum MatchKind: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    /// The query is in the series name.
    case series
    /// The query is in the title.
    case publication
    /// The query is in an author's name.
    case person
    /// The query is in a tag-like value.
    ///
    /// Today that means the publisher and nothing else: a publication carries no tags and
    /// no genres yet, so this group holds publisher matches. Named for what the requirement
    /// asks for rather than for what is indexed, because the group is right and the corpus
    /// is what will grow.
    case tag
}

/// One heading's worth of search results.
///
/// The publications inside stay in the order ``LibraryIndex/arrange(_:query:locale:progress:)``
/// put them, so grouping can never disagree with ranking — a group is a partition of the
/// ranked list, not a second opinion about it.
public struct MatchGroup: Sendable, Equatable, Identifiable {
    public var id: MatchKind { kind }
    public let kind: MatchKind
    public let publications: [Publication]

    public init(kind: MatchKind, publications: [Publication]) {
        self.kind = kind
        self.publications = publications
    }
}

extension LibraryIndex {
    /// Search results, grouped by why each one matched.
    ///
    /// Empty when nothing was typed, and deliberately so: the caller draws the flat shelf
    /// then, and a single group headed "Titles" over an unsearched library would be a
    /// heading that says nothing.
    ///
    /// A publication appears in exactly one group — the kind of its *best* match. A title
    /// that also contains the author's name is one book, and listing it twice would make
    /// the library look bigger than it is.
    public static func grouped(
        _ publications: [Publication],
        query: LibraryQuery,
        locale: Locale = .current,
        progress: (Publication) -> Progress = { _ in .unread }
    ) -> [MatchGroup] {
        let term = query.search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !term.isEmpty else { return [] }

        // Grouped out of the arranged list rather than out of the raw one: the filters,
        // the scope and the ranking have all already been applied, and re-deciding any of
        // them here is how two code paths start disagreeing.
        let ranked = arrange(publications, query: query, locale: locale, progress: progress)

        var order: [MatchKind] = []
        var members: [MatchKind: [Publication]] = [:]
        for publication in ranked {
            guard let rank = rank(publication, matching: term) else { continue }
            let kind = kind(ofRank: rank)
            if members[kind] == nil { order.append(kind) }
            members[kind, default: []].append(publication)
        }
        // Headings in the order their best match came, not in the order the enum is
        // written. A title that starts with what was typed outranks a series that merely
        // contains it, and a fixed heading order would bury the row the reader meant.
        return order.map { MatchGroup(kind: $0, publications: members[$0] ?? []) }
    }

    /// Which group a rank belongs to.
    ///
    /// Ranks 0 and 1 are both the title — one starts with the query and one contains it —
    /// and both are the same answer to "why is this here". The distinction between them is
    /// about order, and order is already settled by the time this is asked.
    static func kind(ofRank rank: Int) -> MatchKind {
        switch rank {
        case 0, 1: .publication
        case 2: .series
        case 3: .person
        default: .tag
        }
    }
}
