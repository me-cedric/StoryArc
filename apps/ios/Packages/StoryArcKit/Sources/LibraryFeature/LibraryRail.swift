internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// One entry of the index down the side of a long shelf: a letter, and the row it moves to.
///
/// The row is named by its publication's identifier rather than by a position, because the
/// scroll is done by `ScrollViewReader` and a position would have to be recounted every time
/// the grid put a heading or a full-span row between two cells. Android's `RailEntry` carries
/// the identifier too and then maps it to an item index, which is the one thing the two
/// platforms cannot share — see `LibraryRail.kt`.
struct RailEntry: Identifiable, Equatable {
    /// The single character the entry draws, or `#` for everything no letter claims.
    let label: String
    /// The first row filed under that label.
    let publicationID: String

    var id: String { label }
}

/// Which letters a shelf can be indexed by, and where each one starts.
///
/// `library-browsing`: "an index runs down its trailing edge, holding one entry for each
/// letter the shelf actually files a row under, in the shelf's own order". Two sorts file a
/// row under a letter and five do not, and the requirement's *A sort no letter describes*
/// scenario says the index is then **absent** rather than drawn and inert.
///
/// **Read off the sort key, never off the section headings.** A section title is a series
/// name, a letter, a year or one translated word for the unplaceable, so a rail built from
/// the headings would be a rail of names — a different control. And it is the *sort key*
/// rather than the raw title, for ``LibrarySections``' reason: `library-browsing`
/// alphabetises a title with its leading article ignored, so *The Sandman* files under S and
/// a label read off the raw title would say T in the middle of the S run.
///
/// Pure and free of SwiftUI, as ``LibrarySections`` and ``LibraryRows`` are and for the same
/// reason — `LibraryRailTests` states the awkward cases once here rather than discovering
/// them per screenshot. Android's `LibraryRail` answers the same cases.
enum LibraryRail {

    /// The letters this shelf offers, in the shelf's own order, or nothing at all.
    ///
    /// Three refusals, and each of them is a real answer the caller draws nothing for:
    ///
    /// - a sort that files no row under a letter,
    /// - a shelf short enough to take in at a glance — ``LibrarySections/threshold``, the
    ///   definition this repository already holds, rather than a second number,
    /// - a shelf whose every row files under one letter, where the index moves nowhere.
    /// - Parameter locale: the language whose alphabet the labels are read in. The reader's,
    ///   from the one caller that draws a shelf; the process's by default, the way
    ///   ``LibrarySections/divide(_:by:locale:)`` defaults.
    static func of(
        _ publications: [Publication],
        sort: LibrarySort,
        locale: Locale = .current
    ) -> [RailEntry] {
        guard publications.count > LibrarySections.threshold else { return [] }

        var entries: [RailEntry] = []
        var seen: Set<String> = []
        for publication in publications {
            guard let label = label(for: publication, sort: sort, locale: locale) else {
                return []
            }
            guard seen.insert(label).inserted else { continue }
            entries.append(RailEntry(label: label, publicationID: publication.id))
        }
        // One letter over the whole shelf is a label rather than an index, and choosing it
        // would move the shelf nowhere. The same shape ``LibrarySections/divide(_:by:locale:)``
        // refuses a single section for.
        return entries.count > 1 ? entries : []
    }

    /// Which letter a row files under, or `nil` when this sort files rows under none.
    ///
    /// The `nil` is the whole of the hide-rather-than-disable decision, and it is checked on
    /// the first row: a sort that answers `nil` answers it for every row, so ``of(_:sort:locale:)``
    /// returns an empty index the moment it sees one.
    private static func label(
        for publication: Publication,
        sort: LibrarySort,
        locale: Locale
    ) -> String? {
        switch sort {
        case .title:
            // The key the shelf is ordered by, so the labels run in the shelf's own order.
            return initial(of: LibraryIndex.sortKey(publication.displayTitle, locale: locale), locale: locale)
        case .series:
            // A publication naming no series is `#`, and every one of them is one contiguous
            // run at the end of the shelf — `LibraryIndex.compareBySeries` puts the whole
            // pile after every series on purpose, so the index never runs a second alphabet
            // through the first.
            guard let series = LibraryIndex.seriesName(of: publication) else { return "#" }
            return initial(of: LibraryIndex.sortKey(series, locale: locale), locale: locale)
        case .lastRead, .progress, .year, .dateAdded, .fileSize:
            // None of these files a row under a letter. Four are continuous, for the reason
            // ``LibrarySections`` gives; a year divides the shelf and is not a letter, and an
            // index of years is a different control from an A-to-Z.
            return nil
        }
    }

    /// What a letter actually scrolls to, by the publication it names.
    ///
    /// **A letter that names the first row of a section scrolls to the section's heading, not
    /// to the row.** A pinned heading is drawn over the top of the scroll view, so a row
    /// anchored at `.top` sits behind it. Measured on Android on 2026-09-11, where the same
    /// rule is written as item arithmetic: the row spanned 1043 to 1259 and the heading 1043
    /// to 1106, so 63 px of a 216 px row was hidden, the top of its cover included. A reader
    /// who asks for M is asking to see the M heading and the first row under it.
    ///
    /// A letter can still name a row that is not its section's first — under a series sort one
    /// *Other* section holds titles filed under many letters — and that row is scrolled to
    /// directly, because no heading names it.
    ///
    /// Empty for an undivided shelf, where the caller scrolls to the publication itself.
    /// Android's `LibraryRail.itemIndexes` is the twin: it counts items because it has no
    /// scroll proxy, and this names an identifier because it has one.
    static func anchors(sections: [LibrarySection]) -> [String: String] {
        var anchors: [String: String] = [:]
        for section in sections {
            guard let first = section.publications.first else { continue }
            anchors[first.id] = section.id
        }
        return anchors
    }

    /// The letter a key files under, or `#` for everything that files under none.
    ///
    /// Uppercased for the reader's locale rather than for the machine's: a Turkish shelf
    /// files *ısı* under *I*, and `uppercased()` with no locale would not. The same rule
    /// ``LibrarySections`` applies to a heading, so a heading and an index entry cannot
    /// disagree about one row.
    private static func initial(of key: String, locale: Locale) -> String {
        guard let first = key.trimmingCharacters(in: .whitespacesAndNewlines).first,
              first.isLetter
        else { return "#" }
        return String(first).uppercased(with: locale)
    }

    /// The width of the rail's hit region. 44 points is the least Apple's guidelines allow a
    /// target, and the rail has the whole of it from the shelf's edge.
    ///
    /// Stated here rather than on ``IndexRail``, which is main-actor isolated and cannot
    /// stand as a nonisolated default argument's value or be read from a plain test.
    static let hitWidth: CGFloat = 44

    /// The padding above the first letter and below the last, inside the hit region. A
    /// finger on it counts as the first or the last letter.
    static let inset: CGFloat = StoryArcSpace.sm

    /// How wide the capsule behind the letters draws, centred in the hit region.
    static let capsuleWidth: CGFloat = 22 + StoryArcSpace.xs * 2

    /// The height one rail entry draws at. ``IndexRail`` draws its letters at this height,
    /// so the view and ``collapsed(_:toFit:entryHeight:)`` can never disagree about how many
    /// of them fit a given space. Stated here rather than on the view, which is main-actor
    /// isolated and cannot stand as a nonisolated default argument's value.
    static let entryHeight: CGFloat = 22

    /// Which of these entries fit a space of the given height, one per ``entryHeight`` —
    /// collapsing to an evenly spaced subset when they do not, the way the system's own
    /// section index falls back to short of room rather than overlapping.
    ///
    /// Photographed in landscape on 2026-09-28: 27 entries of 22 pt need about 600 pt, which
    /// is more than a landscape shelf's height, and the uncollapsed rail ran off both edges of
    /// the screen. **Every input already short enough draws every entry it was given** — this
    /// only ever removes some, never reorders or invents one.
    ///
    /// The subset always keeps the first and the last entry, because those are the ends of
    /// the alphabet a reader reaches for, and spaces the rest evenly between them so no one
    /// run of letters is favoured over another. **A letter this drops is still reachable:**
    /// ``IndexRail`` is one scrubber, and ``RailScrub`` reads the finger's position against
    /// the whole alphabet rather than against the letters drawn, so every entry has a place
    /// under the finger and the bubble names the one it is on.
    static func collapsed(
        _ entries: [RailEntry],
        toFit height: CGFloat,
        entryHeight: CGFloat = LibraryRail.entryHeight
    ) -> [RailEntry] {
        guard entryHeight > 0, height > 0 else { return entries }
        let capacity = max(1, Int((height / entryHeight).rounded(.down)))
        guard entries.count > capacity else { return entries }
        guard capacity > 1 else { return [entries[0]] }

        var kept: [RailEntry] = []
        var lastIndex = -1
        for slot in 0..<capacity {
            let index = slot * (entries.count - 1) / (capacity - 1)
            guard index != lastIndex else { continue }
            kept.append(entries[index])
            lastIndex = index
        }
        return kept
    }
}
