internal import Foundation

internal import StoryArcCore

/// One heading's worth of shelf.
///
/// Its own identity rather than the title, because a title can come back: a shelf sorted by
/// title that runs *Saga · Sabrina · Sandman* divides into three sections of which the
/// middle one is a single stray, and two sections headed "S" are two places on the shelf,
/// not one place listed twice.
struct LibrarySection: Identifiable, Equatable {
    let id: String
    /// What the heading says. A series name, a letter or a year — always data the library
    /// already holds, so a section never needs a string of its own.
    let title: String
    let publications: [Publication]
}

/// How a long shelf is divided.
///
/// `library-browsing`: "when the library holds more publications than a reader can scan,
/// then it is divided by series where a publication declares one, and otherwise by the
/// active sort key, with headings that stay visible while their section is on screen — and
/// the sections follow the sort rather than replacing it".
///
/// That last clause is the whole design. Sections are **contiguous runs of the arranged
/// list**, never a regrouping of it: the shelf stays in exactly the order
/// `LibraryIndex.arrange` put it in, and a heading is opened wherever the key changes. A
/// grouping that gathered every "A" from across a shelf sorted by last-read would silently
/// undo the sort the reader chose, which is the failure this shape exists to avoid.
///
/// Pure and free of SwiftUI so the rule can be asserted directly — `LibrarySectionTests` is
/// the reason the awkward cases below are stated once here rather than discovered per
/// screenshot.
enum LibrarySections {

    /// Above how many publications a shelf earns structure.
    ///
    /// "More than a reader can scan" is the requirement's own phrase, and a number is the
    /// only way to hold it. A phone shows nine covers at once, so twelve is the first count
    /// at which the shelf certainly runs off the bottom with more below — the moment a
    /// reader starts scrolling to look for something rather than seeing it. Below it the
    /// caller draws one uniform run, which is what the requirement's *when* clause asks for.
    static let threshold = 12

    /// The shelf, divided — or nothing at all when it divides into nothing.
    ///
    /// An empty result is a real answer, and the caller draws the plain grid then. Two cases
    /// reach it: a sort with no natural divisions (last read, progress, date added, size —
    /// all continuous, and a heading over a continuum is an invented boundary), and a shelf
    /// whose every publication lands in one section, where a single heading over the whole
    /// grid would be a label rather than a structure.
    static func divide(_ publications: [Publication], by sort: LibrarySort) -> [LibrarySection] {
        guard !publications.isEmpty else { return [] }

        // A series is only worth a heading when the shelf holds more than one of it. A manga
        // library of three hundred one-shots would otherwise become three hundred headings
        // over one cover each, which is less structure than the wall it replaced, not more.
        var shared = sharedSeries(in: publications)
        // And only when the sort keeps it in one place. Sorted by title, *Ashfall #3* is
        // filed under T and *Ashfall #4* under W, with other books between them — two
        // headings reading "Ashfall" are two places on the shelf, and the reader would be
        // right to think the app had lost one of them. So a series the sort scatters is
        // demoted to the sort's own division, which is what "the sections follow the sort
        // rather than replacing it" means when the two disagree.
        shared.subtract(scatteredSeries(publications, sort: sort, sharedSeries: shared))

        let sections = runs(publications, sort: sort, sharedSeries: shared)

        // One section is the whole shelf under a heading, which says nothing the shelf did
        // not already say. A key of `nil` — a sort that divides into nothing — arrives here
        // the same way, as one run, and leaves by the same door.
        guard sections.count > 1 else { return [] }
        // No heading twice, for any key and not only for a series. Sorted by series, a
        // library whose standalone titles fall either side of its first series draws
        // *Other*, then that series, then *Other* again — and a reader reasonably reads the
        // second one as a different pile. Where the sort scatters a key that has nowhere
        // left to be demoted to, the division misdescribes the shelf, and no division is the
        // honest answer.
        guard Set(sections.map(\.title)).count == sections.count else { return [] }
        // And a heading has to earn its row. A phone shows three covers across, so a
        // division averaging fewer than three per heading costs more vertical space in
        // headings and part-empty rows than the covers it introduces — one dense grid
        // becomes a tall column of announcements. That was not a hypothesis: the test
        // corpus, twenty-two unrelated files with a distinct initial each, drew exactly
        // that on a booted simulator, and it reads worse than the wall it replaced, which
        // is the failure this whole requirement exists to fix, arrived at from the other
        // side.
        guard publications.count >= sections.count * Self.coversPerRow else { return [] }
        return sections
    }

    /// How many covers a phone shows across, and so the least a heading may cover.
    private static let coversPerRow = 3

    /// The shelf cut wherever the key changes, in the order it arrived.
    private static func runs(
        _ publications: [Publication],
        sort: LibrarySort,
        sharedSeries: Set<String>
    ) -> [LibrarySection] {
        var sections: [LibrarySection] = []
        var currentKey: String?
        var current: [Publication] = []

        for publication in publications {
            let key = self.key(for: publication, sort: sort, sharedSeries: sharedSeries)
            if key != currentKey {
                if let currentKey, !current.isEmpty {
                    sections.append(section(currentKey, current, at: sections.count))
                }
                currentKey = key
                current = []
            }
            current.append(publication)
        }
        if let currentKey, !current.isEmpty {
            sections.append(section(currentKey, current, at: sections.count))
        }
        return sections
    }

    private static func section(
        _ key: String,
        _ publications: [Publication],
        at index: Int
    ) -> LibrarySection {
        LibrarySection(id: "\(index).\(key)", title: key, publications: publications)
    }

    /// The series the shelf holds more than one of.
    private static func sharedSeries(in publications: [Publication]) -> Set<String> {
        var counts: [String: Int] = [:]
        for publication in publications {
            guard let series = named(publication.series) else { continue }
            counts[series, default: 0] += 1
        }
        return Set(counts.filter { $0.value > 1 }.keys)
    }

    /// The series this sort does not keep together.
    private static func scatteredSeries(
        _ publications: [Publication],
        sort: LibrarySort,
        sharedSeries: Set<String>
    ) -> Set<String> {
        var seen: Set<String> = []
        var scattered: Set<String> = []
        for section in runs(publications, sort: sort, sharedSeries: sharedSeries) {
            guard sharedSeries.contains(section.title) else { continue }
            if !seen.insert(section.title).inserted { scattered.insert(section.title) }
        }
        return scattered
    }

    /// Which heading a publication belongs under, or `nil` when this sort divides into
    /// nothing and the shelf is one run.
    private static func key(
        for publication: Publication,
        sort: LibrarySort,
        sharedSeries: Set<String>
    ) -> String? {
        // Series first, as the requirement words it. It is checked before the sort's own
        // division rather than after because a reader scanning a shelf recognises *Saga*
        // long before they recognise *S*.
        if let series = named(publication.series), sharedSeries.contains(series) {
            return series
        }
        switch sort {
        case .series:
            // Everything the shelf could not put in a series goes in one place under a sort
            // that is *about* series. Filing them under their initials instead would answer
            // a question the reader did not ask, and would scatter the standalone half of a
            // library across twenty headings that all mean "no series".
            return unknown
        case .title:
            return initial(of: publication.displayTitle)
        case .year:
            // The year as the file spells it. A publication with none is not "before
            // everything" — the library simply does not know, and `YearRange` treats an
            // unknown year the same way.
            return publication.year.map(String.init) ?? unknown
        case .lastRead, .progress, .dateAdded, .fileSize:
            // Continuous, every one of them. Where the boundary between "recently" and
            // "a while ago" falls is a decision no file carries, and a heading that invents
            // one would be the app asserting something it does not know.
            return nil
        }
    }

    /// The letter a title files under, or `#` for everything that files under none.
    ///
    /// Uppercased for the reader's locale rather than for the machine's: a Turkish shelf
    /// files *ısı* under *I*, and `uppercased()` with no locale would not.
    private static func initial(of title: String) -> String {
        guard let first = title.trimmingCharacters(in: .whitespacesAndNewlines).first else {
            return unknown
        }
        guard first.isLetter else { return "#" }
        return String(first).uppercased(with: .current)
    }

    /// A series name worth using: present, and not merely whitespace.
    private static func named(_ series: String?) -> String? {
        guard let trimmed = series?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }

    /// The heading for everything the library cannot place.
    ///
    /// A localized string rather than a symbol, because it is the one heading that is a word
    /// rather than data off a file.
    private static var unknown: String {
        String(localized: "library.section.other", bundle: .module, locale: .storyArc)
    }
}
