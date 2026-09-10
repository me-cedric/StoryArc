import StoryArcCore

/// One row of the library: a publication, or a series holding several.
///
/// `library-browsing`: "the library lists that series once, as a single cell carrying the
/// series' own artwork and how many publications it holds", and "a publication that belongs
/// to no series is a row of its own".
///
/// Android's `LibraryRow` is its twin, case for case.
enum LibraryRow: Identifiable, Equatable {
    case one(Publication)
    case series(name: String, members: [Publication])

    /// Stable across arrangements, so a row keeps its place in a list that re-sorts.
    var id: String {
        switch self {
        case let .one(publication): publication.id
        case let .series(name, _): "series:\(name)"
        }
    }

    /// The cover this row draws, and what a tap opens when the row holds one thing.
    var lead: Publication {
        switch self {
        case let .one(publication): publication
        case let .series(_, members): members[0]
        }
    }

    /// How many publications the row stands for, or nil when it stands for itself.
    var count: Int? {
        switch self {
        case .one: nil
        case let .series(_, members): members.count
        }
    }
}

/// How the arranged library becomes rows.
///
/// A reader scans series, not issues. Sixty series of twenty issues is twelve hundred cells,
/// which is what the library drew before this: ``LibrarySections`` divided them into sixty
/// headings, a wall with signposts on it rather than a shelf. Kavita's own client lists
/// series and opens one to reach its issues, and the owner asked for that shape after
/// meeting the other on a phone.
///
/// **A series takes the position of its first member and absorbs the rest.** That is the one
/// decision worth arguing about: gathering every member from across the shelf would undo the
/// sort the reader chose, which is the failure ``LibrarySections`` exists to avoid, and
/// leaving scattered members as separate rows would list one series twice. Taking the first
/// appearance keeps the arrangement's own answer about where the series belongs and still
/// yields exactly one row per series.
///
/// Pure and free of SwiftUI, as ``LibrarySections`` is and for the same reason. Android's
/// `LibraryRows` answers the same cases.
enum LibraryRows {

    /// The arranged list as rows, in the arrangement's own order.
    ///
    /// A series of one is ``LibraryRow/one(_:)``, not a series with a single member: a row
    /// that opens a list holding one thing is a tap the reader did not need to make.
    static func of(_ publications: [Publication]) -> [LibraryRow] {
        var bySeries: [String: [Publication]] = [:]
        for publication in publications {
            guard let series = publication.series, !series.trimmingCharacters(in: .whitespaces).isEmpty
            else { continue }
            bySeries[series, default: []].append(publication)
        }

        var taken: Set<String> = []
        var rows: [LibraryRow] = []
        for publication in publications {
            let series = publication.series.flatMap {
                $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0
            }
            guard let series, let members = bySeries[series], members.count > 1 else {
                rows.append(.one(publication))
                continue
            }
            guard !taken.contains(series) else { continue }
            taken.insert(series)
            rows.append(.series(name: series, members: members))
        }
        return rows
    }
}
