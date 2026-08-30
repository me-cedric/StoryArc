import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// What Home puts on each shelf, and what it deliberately leaves off.
///
/// The two lead shelves are the whole argument of `home-screen`: *where you stopped* and
/// *what to start next* are two questions, and the spec spends five scenarios on the
/// boundary between them. None of that boundary is visible in a screenshot — a series that
/// wrongly appears in Up next looks exactly like one that belongs there — so it is asserted
/// here instead.
@Suite("Home shelves")
struct HomeShelvesTests {

    // MARK: - Fixtures

    private func issue(_ series: String, _ number: String, title: String? = nil) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/\(series)/\(number).cbz"),
            format: .cbz,
            displayTitle: title ?? "\(series) #\(number)",
            series: series,
            number: number,
            origin: .inferred
        )
    }

    private func read(
        _ publication: Publication,
        page: Int,
        of total: Int,
        finished: Bool = false,
        at moment: Date = Date(timeIntervalSince1970: 1_000)
    ) -> ReadingProgress {
        ReadingProgress(
            identity: publication.identity,
            position: .page(index: page, of: total),
            isFinished: finished,
            finishedAt: finished ? moment : nil,
            updatedAt: moment
        )
    }

    /// A lookup of the records given to it, keyed the way the model keys them.
    private func history(_ records: [(Publication, ReadingProgress)]) -> (Publication) -> ReadingProgress? {
        let byID = Dictionary(uniqueKeysWithValues: records.map { ($0.0.id, $0.1) })
        return { byID[$0.id] }
    }

    // MARK: - Up next

    @Test("The issue after the one that was finished is offered")
    func offersTheSuccessor() {
        let first = issue("Saga", "1")
        let second = issue("Saga", "2")
        let progress = history([(first, read(first, page: 9, of: 10, finished: true))])

        let offered = HomeShelves.upNext(in: [first, second], progress: progress)

        #expect(offered.map(\.id) == [second.id])
    }

    @Test("A series with something part-read offers nothing, because Keep reading has it")
    func partReadSeriesIsLeftToKeepReading() {
        // The scenario the spec spends its longest paragraph on, and the one Mihon
        // conflated: a part-read issue and a later unread one are not two offers. The
        // part-read one is in Keep reading, and the later one waits until it is finished.
        let first = issue("Saga", "1")
        let second = issue("Saga", "2")
        let third = issue("Saga", "3")
        let progress = history([
            (first, read(first, page: 9, of: 10, finished: true)),
            (second, read(second, page: 4, of: 10)),
        ])

        #expect(HomeShelves.upNext(in: [first, second, third], progress: progress).isEmpty)
    }

    @Test("A series nothing has been read of offers nothing")
    func unstartedSeriesIsSilent() {
        let first = issue("Saga", "1")
        let second = issue("Saga", "2")

        #expect(HomeShelves.upNext(in: [first, second]) { _ in nil }.isEmpty)
    }

    @Test("A series read to the end offers nothing, silently")
    func exhaustedSeriesIsSilent() {
        let first = issue("Saga", "1")
        let second = issue("Saga", "2")
        let progress = history([
            (first, read(first, page: 9, of: 10, finished: true)),
            (second, read(second, page: 9, of: 10, finished: true)),
        ])

        #expect(HomeShelves.upNext(in: [first, second], progress: progress).isEmpty)
    }

    @Test("A gap in a collection does not re-offer what was skipped")
    func offersAfterTheFurthestFinished() {
        // Issues 1 and 3 read, 2 never obtained. The next thing to read is 4 — offering 2
        // would send a reader back to a hole in their own shelf.
        let one = issue("Saga", "1")
        let two = issue("Saga", "2")
        let three = issue("Saga", "3")
        let four = issue("Saga", "4")
        let progress = history([
            (one, read(one, page: 9, of: 10, finished: true)),
            (three, read(three, page: 9, of: 10, finished: true)),
        ])

        let offered = HomeShelves.upNext(in: [one, two, three, four], progress: progress)

        #expect(offered.map(\.id) == [four.id])
    }

    @Test("Series are offered with the most recently read first")
    func ordersByWhenTheSeriesWasLastRead() {
        let older = issue("Bone", "1")
        let olderNext = issue("Bone", "2")
        let newer = issue("Saga", "1")
        let newerNext = issue("Saga", "2")
        let progress = history([
            (older, read(older, page: 9, of: 10, finished: true, at: Date(timeIntervalSince1970: 10))),
            (newer, read(newer, page: 9, of: 10, finished: true, at: Date(timeIntervalSince1970: 900))),
        ])

        let offered = HomeShelves.upNext(
            in: [older, olderNext, newer, newerNext],
            progress: progress
        )

        #expect(offered.map(\.id) == [newerNext.id, olderNext.id])
    }

    @Test("A publication with no series contributes nothing")
    func standalonePublicationsAreNotASeries() {
        let alone = Publication(
            identity: PublicationIdentity(normalizedPath: "/alone.cbz"),
            format: .cbz,
            displayTitle: "Alone",
            origin: .inferred
        )
        let progress = history([(alone, read(alone, page: 9, of: 10, finished: true))])

        #expect(HomeShelves.upNext(in: [alone], progress: progress).isEmpty)
    }

    // MARK: - Finished

    @Test("Finished publications are grouped by the month they were finished in")
    func groupsFinishedByMonth() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt

        let march = DateComponents(calendar: calendar, year: 2026, month: 3, day: 4).date ?? .now
        let alsoMarch = DateComponents(calendar: calendar, year: 2026, month: 3, day: 28).date ?? .now
        let april = DateComponents(calendar: calendar, year: 2026, month: 4, day: 2).date ?? .now

        let first = issue("Saga", "1")
        let second = issue("Saga", "2")
        let third = issue("Saga", "3")
        let progress = history([
            (first, read(first, page: 9, of: 10, finished: true, at: march)),
            (second, read(second, page: 9, of: 10, finished: true, at: alsoMarch)),
            (third, read(third, page: 9, of: 10, finished: true, at: april)),
        ])

        let groups = HomeShelves.finished(
            in: [first, second, third],
            calendar: calendar,
            progress: progress
        )

        #expect(groups.count == 2)
        // Newest month first, and newest within it.
        #expect(groups.first?.publications.map(\.id) == [third.id])
        #expect(groups.last?.publications.map(\.id) == [second.id, first.id])
    }

    @Test("Nothing finished means no groups rather than an empty one")
    func absentRatherThanEmpty() {
        let first = issue("Saga", "1")
        let progress = history([(first, read(first, page: 4, of: 10))])

        #expect(HomeShelves.finished(in: [first], progress: progress).isEmpty)
    }

    // MARK: - Recently added

    @Test("Publications with no arrival date keep the library's own order")
    func undatedPublicationsSurvive() {
        // A folder copied wholesale reports nothing, and a shelf that emptied itself over
        // that would take the library away from a reader whose books are all present.
        let first = issue("Saga", "1")
        let second = issue("Saga", "2")

        #expect(HomeShelves.recentlyAdded(in: [first, second]).count == 2)
    }

    @Test("The newest arrival leads")
    func newestFirst() {
        var first = issue("Saga", "1")
        var second = issue("Saga", "2")
        first.addedAt = Date(timeIntervalSince1970: 10)
        second.addedAt = Date(timeIntervalSince1970: 900)

        #expect(HomeShelves.recentlyAdded(in: [first, second]).map(\.id) == [second.id, first.id])
    }
}
