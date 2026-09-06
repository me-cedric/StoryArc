import Foundation
import Testing

@testable import StoryArcCore

/// The fallback `local-library` names, asserted against the same table as
/// Android's `FilenameOrderTest`.
///
/// *Nested folder structure becomes series*: "a subfolder whose contents cannot be
/// ordered falls back to case-insensitive natural filename order". A folder of
/// scans whose embedded titles are absent or identical carries nothing else, so
/// the filename is the only thing left to order by. Add a case here, add it there.
@Suite("Filename order")
struct FilenameOrderTests {

    private func publication(
        _ title: String,
        series: String? = nil,
        number: String? = nil,
        file: String? = nil
    ) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: file.map { "/library/Kagurabachi/\($0)" }),
            format: .cbz,
            displayTitle: title,
            series: series,
            number: number,
            origin: .inferred
        )
    }

    private func files(_ publications: [Publication]) -> [String] {
        publications.map { publication in
            let path = publication.identity.normalizedPath ?? ""
            return String(path.split(separator: "/", omittingEmptySubsequences: true).last ?? "")
        }
    }

    private let english = Locale(identifier: "en")

    @Test("A chapter ten follows a chapter two, because the digits compare as numbers")
    func digitsCompareAsNumbers() {
        let library = [
            publication("Chapter", series: "Kagurabachi", file: "ch10.cbz"),
            publication("Chapter", series: "Kagurabachi", file: "ch1.cbz"),
            publication("Chapter", series: "Kagurabachi", file: "ch2.cbz"),
        ]
        let sorted = LibraryIndex.arrange(library, query: LibraryQuery(sort: .series), locale: english)
        #expect(files(sorted) == ["ch1.cbz", "ch2.cbz", "ch10.cbz"])
    }

    @Test("Case alone does not decide, so a capital chapter two still precedes chapter ten")
    func caseDoesNotDecide() {
        let library = [
            publication("Chapter", series: "Kagurabachi", file: "CH10.cbz"),
            publication("Chapter", series: "Kagurabachi", file: "Ch2.cbz"),
            publication("Chapter", series: "Kagurabachi", file: "ch1.cbz"),
        ]
        let sorted = LibraryIndex.arrange(library, query: LibraryQuery(sort: .series), locale: english)
        #expect(files(sorted) == ["ch1.cbz", "Ch2.cbz", "CH10.cbz"])
    }

    @Test("A series that carries issue numbers keeps them, and the filename never fires")
    func numbersOutrankTheFilename() {
        let library = [
            publication("Chapter", series: "Kagurabachi", number: "2", file: "z.cbz"),
            publication("Chapter", series: "Kagurabachi", number: "10", file: "a.cbz"),
        ]
        let sorted = LibraryIndex.arrange(library, query: LibraryQuery(sort: .series), locale: english)
        #expect(files(sorted) == ["z.cbz", "a.cbz"])
    }

    @Test("A title sort still files by the collated title, not by the filename")
    func collationSurvivesTheFallback() {
        let library = [
            publication("The Sandman", file: "a.cbz"),
            publication("Akira", file: "z.cbz"),
        ]
        let sorted = LibraryIndex.arrange(library, query: LibraryQuery(sort: .title), locale: english)
        #expect(sorted.map(\.displayTitle) == ["Akira", "The Sandman"])
    }

    @Test("A tie under any other sort files by the collated title, because the shelf is not a folder")
    func aTiedShelfKeepsTheCollatedTitle() {
        let library = [
            publication("Maus II", file: "Maus II.cbz"),
            publication("Maus", file: "Maus.cbz"),
        ]
        let sorted = LibraryIndex.arrange(library, query: LibraryQuery(sort: .year), locale: english)
        #expect(sorted.map(\.displayTitle) == ["Maus", "Maus II"])
    }

    @Test("A series of server chapters keeps the collated title, because a chapter has no filename")
    func aSeriesWithNoFilesKeepsTheCollatedTitle() {
        let library = [
            publication("A Zoo", series: "Kagurabachi"),
            publication("Bee", series: "Kagurabachi"),
        ]
        let sorted = LibraryIndex.arrange(library, query: LibraryQuery(sort: .series), locale: english)
        #expect(sorted.map(\.displayTitle) == ["Bee", "A Zoo"])
    }
}
