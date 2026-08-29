import Foundation
import Testing

@testable import StoryArcCore

/// Where one issue sits relative to its neighbours, and what the shelf offers to
/// resume — asserted against the same table as Android's `LibrarySequenceTest`.
///
/// Split from `LibraryIndexTests` when that file passed the length the linter
/// allows. The filtering rules stayed there; ordering within a series and the
/// continue-reading row came here.
@Suite("Library sequence")
struct LibrarySequenceTests {

    private func publication(
        _ title: String,
        series: String? = nil,
        number: String? = nil,
        authors: [String] = [],
        publisher: String? = nil,
        format: PublicationFormat = .cbz,
        year: Int? = nil,
        language: String? = nil,
        genres: [String] = [],
        tags: [String] = [],
        fileSize: Int64? = nil,
        addedAt: Date? = nil,
        source: UUID? = nil
    ) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/library/\(title)"),
            format: format,
            displayTitle: title,
            series: series,
            number: number,
            authors: authors,
            publisher: publisher,
            year: year,
            language: language,
            genres: genres,
            tags: tags,
            origin: .inferred,
            sourceID: source,
            fileSize: fileSize,
            addedAt: addedAt
        )
    }

    private func titles(_ publications: [Publication]) -> [String] {
        publications.map(\.displayTitle)
    }

    private let english = Locale(identifier: "en")

    // MARK: - Next in series

    @Test("The next issue is the one after this number, not the next row")
    func nextInSeries() throws {
        let library = [
            publication("Bone #10", series: "Bone", number: "10"),
            publication("Bone #2", series: "Bone", number: "2"),
            publication("Bone #9", series: "Bone", number: "9"),
            publication("Akira", series: "Akira", number: "1"),
        ]
        let second = try #require(library.first { $0.number == "2" })
        let next = LibraryIndex.next(after: second, in: library)
        #expect(next?.displayTitle == "Bone #9")
    }

    @Test("The last issue in a series has no next")
    func lastInSeries() throws {
        let library = [
            publication("Bone #1", series: "Bone", number: "1"),
            publication("Bone #2", series: "Bone", number: "2"),
        ]
        let last = try #require(library.last)
        #expect(LibraryIndex.next(after: last, in: library) == nil)
    }

    @Test("A publication with no series has no next, however many neighbours it has")
    func noSeriesNoNext() {
        let alone = publication("Watchmen")
        #expect(LibraryIndex.next(after: alone, in: [alone, publication("Akira")]) == nil)
    }

    // MARK: - Previous in series

    @Test("The previous issue is the one before this number, not the row above")
    func previousInSeries() throws {
        let library = [
            publication("Bone #10", series: "Bone", number: "10"),
            publication("Bone #2", series: "Bone", number: "2"),
            publication("Bone #9", series: "Bone", number: "9"),
            publication("Akira", series: "Akira", number: "1"),
        ]
        let tenth = try #require(library.first { $0.number == "10" })
        #expect(LibraryIndex.previous(before: tenth, in: library)?.displayTitle == "Bone #9")
    }

    @Test("The first issue in a series has no previous")
    func firstInSeries() throws {
        let library = [
            publication("Bone #1", series: "Bone", number: "1"),
            publication("Bone #2", series: "Bone", number: "2"),
        ]
        let first = try #require(library.first)
        #expect(LibraryIndex.previous(before: first, in: library) == nil)
    }

    @Test("A publication with no series has no previous either")
    func noSeriesNoPrevious() {
        let alone = publication("Watchmen")
        #expect(LibraryIndex.previous(before: alone, in: [alone, publication("Akira")]) == nil)
    }

    // MARK: - Continue reading

    @Test("Continue reading holds only what is in progress, most recent first")
    func continueRow() {
        let akira = publication("Akira")
        let bone = publication("Bone")
        let maus = publication("Maus")
        let states: [String: LibraryIndex.Progress] = [
            akira.id: .init(state: .inProgress, fraction: 0.2, lastReadAt: Date(timeIntervalSince1970: 100)),
            bone.id: .init(state: .inProgress, fraction: 0.8, lastReadAt: Date(timeIntervalSince1970: 300)),
            maus.id: .init(state: .finished, fraction: 1, lastReadAt: Date(timeIntervalSince1970: 400)),
        ]
        let row = LibraryIndex.continueReading([akira, bone, maus]) { states[$0.id] ?? .unread }
        #expect(titles(row) == ["Bone", "Akira"])
    }

    @Test("Continue reading is empty rather than a header over a gap")
    func continueRowEmpty() {
        #expect(LibraryIndex.continueReading([publication("Akira")]) { _ in .unread }.isEmpty)
    }
}
