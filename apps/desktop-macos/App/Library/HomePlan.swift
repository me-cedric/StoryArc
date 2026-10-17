import Foundation
import StoryArcCore

/// What Home shows, in which order, and which shelf is absent.
///
/// `home-screen` on a desktop: the window opens on Home with Keep reading and Up next, and
/// an empty shelf is absent rather than drawn empty. Keep reading is the library's own
/// `continueReading` order, most recently read first; Up next is the first unread issue
/// after each finished series, in the order the series were finished. Pure, over the
/// facts the model already holds. Task 2.23c.
struct HomePlan: Equatable, Sendable {
    let keepReading: [Publication]
    let upNext: [Publication]
    /// Keep reading's publications that cannot be opened right now. They keep their place,
    /// dimmed: `home-screen` says a row that shrinks with the network reads as lost reading.
    var unreadable: Set<String> = []

    var isEmpty: Bool { keepReading.isEmpty && upNext.isEmpty }

    /// - Parameters:
    ///   - continueReading: the model's in-progress list, already ordered.
    ///   - finished: publications marked finished, most recently finished first.
    ///   - next: the model's answer for what follows a publication.
    static func make(
        continueReading: [Publication],
        finished: [Publication],
        next: (Publication) -> Publication?,
        isUnread: (Publication) -> Bool,
        isReadable: (Publication) -> Bool = { _ in true }
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
        let unreadable = Set(continueReading.filter { !isReadable($0) }.map(\.id))
        return HomePlan(keepReading: continueReading, upNext: upNext, unreadable: unreadable)
    }
}
