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
}

/// The index itself, down the trailing edge of the shelf.
///
/// `library-browsing`'s *The index without sight* scenario is the reason for every
/// accessibility line here rather than an afterthought about them:
///
/// - the whole rail is one named container, so a screen reader announces *Alphabetical
///   index* once instead of announcing twenty-seven unexplained characters,
/// - every entry is a real `Button` with a spoken label naming the letter it moves to,
///   because a single drawn character is not an instruction,
/// - nothing here is the only statement of anything: the shelf's own section headings say
///   the same thing in the content, so a reader who never meets the rail loses nothing.
struct IndexRail: View {

    /// How much of the shelf's width the rail takes.
    ///
    /// Stated rather than measured, because the shelf has to reserve it *before* the rail is
    /// laid out: the rail is an `.overlay(alignment: .trailing)`, so a shelf that did not
    /// inset itself drew its last column underneath it. Android's `RAIL_WIDTH` is the twin
    /// and its frames are where the defect was seen.
    ///
    /// 22 pt of entry, `xs` of padding on each side of it, and `xs` again to the edge.
    static let width: CGFloat = 22 + StoryArcSpace.xs * 3

    @Environment(\.theme) private var theme

    let entries: [RailEntry]
    /// Where a chosen letter sends the shelf.
    let onChoose: (RailEntry) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(entries) { entry in
                Button { onChoose(entry) } label: {
                    Text(entry.label)
                        .textRole(.caption)
                        .monospacedDigit()
                        .foregroundStyle(theme.palette.textSecondary)
                        // A fixed, small target so a shelf holding every letter still fits
                        // one column. 22 points is the least a letter can be tapped at
                        // reliably, and the rail is centred rather than stretched so it
                        // clips instead of pushing the covers about.
                        .frame(width: 22, height: 22)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("library.index.jump \(entry.label)", bundle: .module))
            }
        }
        // **The type is capped, because the box is.** Each entry declares a 22-point frame so
        // a shelf holding every letter fits one column. At the largest accessibility size the
        // letters grew and the frames did not, so they overlapped into one illegible vertical
        // smear -- photographed at `UICTContentSizeCategoryAccessibilityXXXL` on 2026-09-11.
        //
        // Capping is what Apple's own section index does, and it is not a loss of access:
        // `library-browsing`'s *The index without sight* requires the rail to be reachable and
        // operable without sight, which it is -- every entry is a button with a spoken label
        // -- and the shelf's own section headings say the same thing in the content at full
        // size. An illegible rail serves nobody; a small legible one beside readable headings
        // serves everybody. Android clamps the same way, with its 24 dp `size`.
        .dynamicTypeSize(...DynamicTypeSize.large)
        .padding(.vertical, StoryArcSpace.sm)
        .padding(.horizontal, StoryArcSpace.xs)
        .background(theme.palette.surfaceOverlay, in: .capsule)
        .padding(.trailing, StoryArcSpace.xs)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("library.index", bundle: .module))
    }
}
