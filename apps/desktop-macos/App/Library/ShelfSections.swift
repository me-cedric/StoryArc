import Foundation
import StoryArcCore

/// One heading's worth of shelf. Its own id rather than the title, because a title can
/// come back: two runs headed "S" are two places on the shelf.
struct ShelfSection: Identifiable, Equatable {
    let id: String
    let title: String
    let publications: [Publication]
}

/// How a long shelf is divided, and the letters it can be jumped to by.
///
/// `library-browsing`, *Sectioning a long library*, *An index down the side of a long
/// shelf* and *A sort no letter describes*. A Mac copy of `LibrarySections.divide` and
/// `LibraryRail.of`, which are internal to `LibraryFeature`: making them public is a parent
/// edit under `apps/ios` (task 5.12's family), and until then `ShelfSectionTests` holds the
/// copy to the same cases the iOS tests name. Sections are contiguous runs of the arranged
/// shelf, never a regrouping of it, so they follow the sort rather than replace it.
enum ShelfSections {
    /// Above how many publications a shelf earns structure, as `LibrarySections.threshold`.
    static let threshold = 12

    /// The shelf divided, or nothing when it divides into nothing.
    ///
    /// - Parameter columns: how many cells the layout shows across. A division averaging
    ///   fewer than that per heading costs more in headings and part-empty rows than it
    ///   gives, so the grid refuses what the list, at one column, accepts.
    static func divide(
        _ publications: [Publication], by sort: LibrarySort, columns: Int, locale: Locale
    ) -> [ShelfSection] {
        guard publications.count > threshold else { return [] }
        var shared = sharedSeries(in: publications)
        shared.subtract(scattered(publications, sort: sort, sharedSeries: shared, locale: locale))
        let sections = runs(publications, sort: sort, sharedSeries: shared, locale: locale)
        // One section is a label, not a structure; a division must hold every row; no heading
        // twice; and every heading earns its row.
        guard sections.count > 1,
              sections.reduce(0, { $0 + $1.publications.count }) == publications.count,
              Set(sections.map(\.title)).count == sections.count,
              publications.count >= sections.count * max(1, columns)
        else { return [] }
        return sections
    }

    /// One entry per letter the shelf files a row under, in the shelf's own order, each
    /// pointing at the first row filed there; `#` for a row filed under no letter. Empty for
    /// a sort no letter describes, and for a shelf short enough to take in at a glance.
    static func index(_ publications: [Publication], sort: LibrarySort, locale: Locale) -> [ShelfIndexEntry] {
        guard publications.count > threshold else { return [] }
        var entries: [ShelfIndexEntry] = []
        var seen: Set<String> = []
        for publication in publications {
            guard let label = letter(for: publication, sort: sort, locale: locale) else { return [] }
            guard seen.insert(label).inserted else { continue }
            entries.append(ShelfIndexEntry(label: label, publicationID: publication.id))
        }
        return entries.count > 1 ? entries : []
    }

    private static func letter(for publication: Publication, sort: LibrarySort, locale: Locale) -> String? {
        switch sort {
        case .title:
            initial(of: LibraryIndex.sortKey(publication.displayTitle, locale: locale), locale: locale)
        case .series:
            LibraryIndex.seriesName(of: publication)
                .map { initial(of: LibraryIndex.sortKey($0, locale: locale), locale: locale) } ?? "#"
        case .lastRead, .progress, .year, .dateAdded, .fileSize:
            nil
        }
    }

    private static func runs(
        _ publications: [Publication], sort: LibrarySort, sharedSeries: Set<String>, locale: Locale
    ) -> [ShelfSection] {
        var sections: [ShelfSection] = []
        var currentKey: String?
        var current: [Publication] = []
        func close() {
            if let currentKey, !current.isEmpty {
                let id = "\(sections.count).\(currentKey)"
                sections.append(ShelfSection(id: id, title: currentKey, publications: current))
            }
        }
        for publication in publications {
            let key = self.key(for: publication, sort: sort, sharedSeries: sharedSeries, locale: locale)
            if key != currentKey {
                close()
                currentKey = key
                current = []
            }
            current.append(publication)
        }
        close()
        return sections
    }

    private static func sharedSeries(in publications: [Publication]) -> Set<String> {
        var counts: [String: Int] = [:]
        for publication in publications {
            guard let series = LibraryIndex.seriesName(of: publication) else { continue }
            counts[series, default: 0] += 1
        }
        return Set(counts.filter { $0.value > 1 }.keys)
    }

    /// The series this sort does not keep together, demoted to the sort's own division.
    private static func scattered(
        _ publications: [Publication], sort: LibrarySort, sharedSeries: Set<String>, locale: Locale
    ) -> Set<String> {
        var seen: Set<String> = []
        var scattered: Set<String> = []
        for section in runs(publications, sort: sort, sharedSeries: sharedSeries, locale: locale)
        where sharedSeries.contains(section.title) && !seen.insert(section.title).inserted {
            scattered.insert(section.title)
        }
        return scattered
    }

    private static func key(
        for publication: Publication, sort: LibrarySort, sharedSeries: Set<String>, locale: Locale
    ) -> String? {
        if let series = LibraryIndex.seriesName(of: publication), sharedSeries.contains(series) { return series }
        switch sort {
        case .series: return other
        case .title: return initial(of: LibraryIndex.sortKey(publication.displayTitle, locale: locale), locale: locale)
        case .year: return publication.year.map(String.init) ?? other
        case .lastRead, .progress, .dateAdded, .fileSize: return nil
        }
    }

    private static func initial(of key: String, locale: Locale) -> String {
        guard let first = key.trimmingCharacters(in: .whitespacesAndNewlines).first, first.isLetter else { return "#" }
        return String(first).uppercased(with: locale)
    }

    /// The heading for everything the library cannot place.
    private static var other: String { String(localized: "desktop.library.section.other") }
}

/// One letter of the index, and the first row filed under it.
struct ShelfIndexEntry: Identifiable, Equatable {
    let label: String
    let publicationID: String

    var id: String { label }
}
