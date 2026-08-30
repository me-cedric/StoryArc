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
    /// only way to hold it. Twenty-four is four rows on a phone and two on a tablet: enough
    /// that a wall of covers has begun, few enough that a shelf a reader can take in at a
    /// glance is left alone. Below it the caller draws one uniform run, which is what the
    /// requirement's *when* clause asks for.
    static let threshold = 24

    /// The shelf, divided — or nothing at all when it divides into nothing.
    ///
    /// An empty result is a real answer, and the caller draws the plain grid then. Two cases
    /// reach it: a sort with no natural divisions (last read, progress, date added, size —
    /// all continuous, and a heading over a continuum is an invented boundary), and a shelf
    /// whose every publication lands in one section, where a single heading over the whole
    /// grid would be a label rather than a structure.
    static func divide(_ publications: [Publication], by sort: LibrarySort) -> [LibrarySection] {
        guard !publications.isEmpty else { return [] }

        // Two passes, because a series is only worth a heading when the shelf holds more
        // than one of it. A manga library of three hundred one-shots would otherwise become
        // three hundred headings over one cover each, which is less structure than the wall
        // it replaced, not more.
        let shared = sharedSeries(in: publications)

        var sections: [LibrarySection] = []
        var currentKey: String?
        var current: [Publication] = []

        for publication in publications {
            let key = self.key(for: publication, sort: sort, sharedSeries: shared)
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

        // One section is the whole shelf under a heading, which says nothing the shelf did
        // not already say. A key of `nil` — a sort that divides into nothing — arrives here
        // the same way, as one run, and leaves by the same door.
        return sections.count > 1 ? sections : []
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
        case .title, .series:
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
