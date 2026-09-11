import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// How many columns a heading has to earn, which is the one question the two layouts answer
/// differently.
///
/// `library-browsing`'s *Sectioning a long library* divides "the library", not the grid, so
/// it binds the list as much. The grid still refuses a division averaging fewer than three
/// rows a heading, because a heading there costs a band plus the part-empty row under it. A
/// list has one column: a heading costs one row and wastes nothing, so the same shelf
/// divides. The corpus below is the shelf that separates them — measured on 2026-09-11, a
/// library of 218 publications drew pinned headings in the grid and none in the list.
///
/// ``LibrarySectionTests`` holds every other rule, and holds them at the grid's column count.
/// This is a second file rather than a longer one because that suite reached SwiftLint's
/// 400-line cap, which is the seam ``LibraryFeatureSource`` was cut on for the same reason.
@Suite("Library section columns")
struct LibrarySectionColumnTests {

    private func publication(_ title: String, series: String? = nil) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/\(title)"),
            format: .cbz,
            displayTitle: title,
            series: series,
            origin: .inferred
        )
    }

    private func series(_ name: String, _ count: Int) -> [Publication] {
        (1...count).map { publication("\(name) #\($0)", series: name) }
    }

    /// Forty-seven rows over twenty-five initials, which averages 1.88 rows a heading.
    ///
    /// The shape the measured shelf collapses to once every series is one row. The average
    /// sits under a grid row of three and over a list row of one, so this one corpus decides
    /// both directions.
    private func sparseAlphabet() -> [Publication] {
        Array("ABCDEFGHIJKLMNOPQRSTUVWXY").enumerated().flatMap { index, letter in
            (1...(index < 22 ? 2 : 1)).map { publication("\(letter)shfall \($0)") }
        }
    }

    /// The shelf divided for an English reader, at the column count the caller states.
    ///
    /// The language is named rather than taken from the host, for the reason
    /// ``LibrarySectionTests`` gives: a heading is the initial of the sort key, and the sort
    /// key drops a leading article in the reader's language.
    private func divide(
        _ shelf: [Publication],
        by sort: LibrarySort,
        columns: Int
    ) -> [LibrarySection] {
        LibrarySections.divide(shelf, by: sort, columns: columns, locale: Locale(identifier: "en"))
    }

    @Test("A shelf of one column divides where the same shelf of three columns is refused")
    func oneColumnDividesWhatThreeColumnsRefuse() {
        let shelf = sparseAlphabet()

        #expect(shelf.count == 47)
        let sections = divide(shelf, by: .title, columns: 1)

        #expect(sections.count == 25)
        #expect(sections.map(\.title) == "ABCDEFGHIJKLMNOPQRSTUVWXY".map(String.init))
        #expect(sections.flatMap(\.publications).map(\.displayTitle) == shelf.map(\.displayTitle))
    }

    @Test("The same shelf of three columns is still refused, so the grid is unchanged")
    func threeColumnsStillRefuseTheSparseShelf() {
        let shelf = sparseAlphabet()

        #expect(divide(shelf, by: .title, columns: 3).isEmpty)
        #expect(
            LibrarySections.divide(shelf, by: .title, locale: Locale(identifier: "en")).isEmpty,
            "three columns is the default, so a caller naming none is the grid"
        )
    }

    /// One column relaxes the row guard and nothing else.
    @Test("A single column buys nothing past the other three refusals")
    func oneColumnKeepsTheOtherRefusals() {
        let eitherSide = [publication("archive-comment")]
            + series("Ashfall", 6)
            + [publication("truncated"), publication("zip64"), publication("tar-store")]

        #expect(divide([], by: .title, columns: 1).isEmpty, "an empty shelf")
        #expect(divide(series("Ashfall", 8), by: .series, columns: 1).isEmpty, "one section")
        #expect(divide(eitherSide, by: .series, columns: 1).isEmpty, "a heading twice")
    }

    /// A division that holds part of the shelf hides the rest of it, in both layouts.
    ///
    /// The key is `nil` for everything a continuous sort cannot place, and a series the shelf
    /// holds more than one of keeps its name under every sort — so this shelf divided into
    /// its two series and dropped the two standalone titles. Measured on Android first, at
    /// eight rows in and six rows out, and the guard is written the same way on both sides.
    @Test("A division holds every row of the shelf, under every sort")
    func aDivisionHoldsEveryRow() {
        let shelf = series("Ashfall", 3) + series("Bellwether", 3)
            + [publication("Dovetail"), publication("Cinderpath")]

        for sort in LibrarySort.allCases {
            let sections = divide(shelf, by: sort, columns: 1)
            if sections.isEmpty { continue }
            #expect(
                sections.flatMap(\.publications).count == shelf.count,
                "\(sort) divided \(shelf.count) rows into sections holding \(sections.flatMap(\.publications).count)"
            )
        }
    }
}
