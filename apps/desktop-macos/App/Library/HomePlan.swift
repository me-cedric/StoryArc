import Foundation
import StoryArcCore

/// What Home shows, in which order, and which shelf is absent.
///
/// `home-screen` on a desktop: the window opens on Home with Keep reading and Up next, then
/// Recently added, then Finished last, and an empty shelf is absent rather than drawn empty.
/// Keep reading is the library's own `continueReading` order, most recently read first; Up
/// next is the first unread issue after each finished series, in the order the series were
/// finished. Recently added and Finished hold a bounded number, and a shelf that holds more
/// says so, so its heading can lead to the rest in the library (*Every shelf leads somewhere
/// exhaustive*). Pinned shelves are wave 3's, with collections (task 3.15a). Pure, over the
/// facts the model already holds; the rules are `HomeShelves`' from `LibraryFeature`, which
/// keeps them internal. Tasks 2.23c and the wave 2 walk.
struct HomePlan: Equatable, Sendable {
    /// How many Recently added holds, as `HomeShelves.shelfLength`.
    static let shelfLength = 12
    /// How many finished publications Home lists, as `HomeShelves.finished`'s limit.
    static let finishedLength = 24

    /// The finished publications of one month, the month's first instant as its id.
    struct FinishedMonth: Equatable, Sendable, Identifiable {
        let month: Date
        let publications: [Publication]

        var id: Date { month }
    }

    let keepReading: [Publication]
    let upNext: [Publication]
    /// Keep reading's publications that cannot be opened right now. They keep their place,
    /// dimmed: `home-screen` says a row that shrinks with the network reads as lost reading.
    var unreadable: Set<String> = []
    var recentlyAdded: [Publication] = []
    var recentlyAddedHasMore = false
    var finished: [FinishedMonth] = []
    var finishedHasMore = false

    var isEmpty: Bool { keepReading.isEmpty && upNext.isEmpty && recentlyAdded.isEmpty && finished.isEmpty }

    /// - Parameters:
    ///   - continueReading: the model's in-progress list, already ordered.
    ///   - finished: publications marked finished, most recently finished first.
    ///   - next: the model's answer for what follows a publication.
    ///   - library: everything on the shelf, for Recently added.
    ///   - finishedAt: when a finished publication was finished, for the month it files under.
    static func make(
        continueReading: [Publication],
        finished: [Publication],
        next: (Publication) -> Publication?,
        isUnread: (Publication) -> Bool,
        isReadable: (Publication) -> Bool = { _ in true },
        library: [Publication] = [],
        finishedAt: (Publication) -> Date? = { _ in nil },
        calendar: Calendar = .current
    ) -> HomePlan {
        var upNext: [Publication] = []
        let inProgress = Set(continueReading.map(\.id))
        for done in finished {
            guard let following = next(done), isUnread(following),
                  !inProgress.contains(following.id),
                  !upNext.contains(where: { $0.id == following.id })
            else { continue }
            upNext.append(following)
        }
        var plan = HomePlan(
            keepReading: continueReading, upNext: upNext,
            unreadable: Set(continueReading.filter { !isReadable($0) }.map(\.id))
        )
        let arrivals = library.sorted { arrived($0) > arrived($1) }
        plan.recentlyAdded = Array(arrivals.prefix(shelfLength))
        plan.recentlyAddedHasMore = arrivals.count > shelfLength
        plan.finished = months(of: Array(finished.prefix(finishedLength)), finishedAt: finishedAt, calendar: calendar)
        plan.finishedHasMore = finished.count > finishedLength
        return plan
    }

    /// When a publication arrived, as `HomeShelves.arrived`: the date it was added, else the
    /// file's own date. One with neither keeps the library's order at the end, rather than
    /// being dropped from the shelf.
    static func arrived(_ publication: Publication) -> Date {
        publication.addedAt ?? publication.modifiedAt ?? .distantPast
    }

    /// The finished publications grouped by month, newest month first, each month in the
    /// order given. A month rather than a day: a timeline of days is a heading over every row.
    private static func months(
        of finished: [Publication], finishedAt: (Publication) -> Date?, calendar: Calendar
    ) -> [FinishedMonth] {
        var order: [Date] = []
        var members: [Date: [Publication]] = [:]
        for publication in finished {
            let date = finishedAt(publication) ?? .distantPast
            let month = calendar.dateInterval(of: .month, for: date)?.start ?? date
            if members[month] == nil { order.append(month) }
            members[month, default: []].append(publication)
        }
        return order.sorted(by: >).map { FinishedMonth(month: $0, publications: members[$0] ?? []) }
    }
}
