internal import Foundation

internal import StoryArcCore

/// What Home is made of, as arithmetic rather than as views.
///
/// Every shelf below is a projection over publications the app already holds and reading
/// records it already wrote. Nothing here takes a connection, a client or a completion
/// handler, and that is the point rather than a convenience: `home-screen` requires the
/// surface to render "complete and immediately" with every source unreachable, and the
/// cheapest way to keep a promise like that is to have nothing to break. Plex's documented
/// failure is the counter-example — a continue row assembled per server, so home becomes a
/// fragment of the reader's own history whenever one of them is slow.
///
/// Pure and free of SwiftUI so the rules are testable without a screen: which series earns
/// a place in *Up next*, and which one silently earns none, is the part of Home that is
/// easy to get subtly wrong and impossible to see wrong in a screenshot.
enum HomeShelves {

    /// How many a Home shelf holds. Home is never exhaustive; the library is, and every
    /// heading leads there.
    static let shelfLength = 12

    // MARK: - Up next

    /// The next unread issue of each series the reader has started.
    ///
    /// Komga's *On Deck*, and `home-screen` splits it from *Keep reading* deliberately:
    /// *where you stopped* and *what to start next* are two questions, and one row
    /// answering both answers neither. Mihon conflated them and has been arguing about it
    /// in its issue tracker for years.
    ///
    /// Three rules, each of them a scenario in the spec:
    ///
    /// - A series with something **part-read** contributes nothing. That issue is in Keep
    ///   reading, and the two shelves never offer the same series at the same time.
    /// - A series with nothing **finished** contributes nothing. Nothing has been started,
    ///   so there is no *next*.
    /// - A series whose every issue is read contributes nothing, silently.
    ///
    /// Ordering the issues is left to ``LibraryIndex/next(after:in:)`` rather than redone
    /// here: issue numbers are strings — "3.5" and "Annual 1" are both real — and the
    /// parsing of them is asserted against the same table on both platforms. A second
    /// implementation of it on this screen is exactly how the two would drift.
    static func upNext(
        in library: [Publication],
        limit: Int = shelfLength,
        progress: (Publication) -> ReadingProgress?
    ) -> [Publication] {
        let started = Dictionary(grouping: library.filter { $0.series != nil }) { $0.series ?? "" }

        let offered = started.values.compactMap { issues -> (Publication, Date)? in
            guard !issues.contains(where: { isPartRead($0, progress) }) else { return nil }

            let finished = issues.filter { progress($0)?.isFinished == true }
            // The finished issue that no *other finished issue* follows: the furthest the
            // reader has got. Asking the same question of the finished ones alone is what
            // makes a gap in a collection harmless — issues 1 and 3 read, 2 missing, and
            // the shelf still offers 4 rather than re-offering 2.
            guard let furthest = finished.first(where: { LibraryIndex.next(after: $0, in: finished) == nil }),
                  let candidate = LibraryIndex.next(after: furthest, in: issues),
                  isUnread(candidate, progress)
            else { return nil }

            return (candidate, progress(furthest)?.updatedAt ?? .distantPast)
        }

        return
            offered
            .sorted { left, right in
                if left.1 != right.1 { return left.1 > right.1 }
                // A stable tiebreak, so two series finished in the same second do not
                // trade places between redraws.
                return left.0.displayTitle < right.0.displayTitle
            }
            .prefix(limit)
            .map(\.0)
    }

    // MARK: - Recently added

    /// The most recent arrivals, newest first.
    ///
    /// Not filtered on having a date. A file system does not always answer *when did this
    /// arrive* — a folder copied wholesale, a share that reports nothing, an archive
    /// restored from a backup — and a shelf that emptied itself over that would take the
    /// library away from a reader whose books are all perfectly present. When nothing has
    /// a date the order is the library's own, which is the best answer available and not a
    /// wrong one.
    static func recentlyAdded(in library: [Publication], limit: Int = shelfLength) -> [Publication] {
        library
            .sorted { arrived($0) > arrived($1) }
            .prefix(limit)
            .map { $0 }
    }

    static func arrived(_ publication: Publication) -> Date {
        publication.addedAt ?? publication.modifiedAt ?? .distantPast
    }

    // MARK: - Finished

    /// What the reader has finished, in the month they finished it.
    ///
    /// Apple Books' idea, and it costs nothing: `reading-progress` already stamps a
    /// completion date, so the only thing missing was somewhere to show it. A month rather
    /// than a day, because a timeline of single days is a list with a heading over every
    /// row.
    struct FinishedGroup: Identifiable, Equatable {
        /// The first instant of the month, which is also the sort key.
        let id: Date
        let publications: [Publication]
    }

    static func finished(
        in library: [Publication],
        limit: Int = 24,
        calendar: Calendar = .current,
        progress: (Publication) -> ReadingProgress?
    ) -> [FinishedGroup] {
        let dated = library.compactMap { publication -> (Publication, Date)? in
            guard let record = progress(publication), record.isFinished else { return nil }
            // `finishedAt` where it exists, and the last write where it does not: a record
            // written before completion dates were kept is still a finished publication,
            // and dropping it would make the shelf shorter the older the reader's history.
            return (publication, record.finishedAt ?? record.updatedAt)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(limit)

        let months = Dictionary(grouping: dated) { entry in
            calendar.dateInterval(of: .month, for: entry.1)?.start ?? entry.1
        }

        return
            months
            .map { FinishedGroup(id: $0.key, publications: $0.value.map(\.0)) }
            .sorted { $0.id > $1.id }
    }

    // MARK: - Never opened

    /// What the reader has never opened, newest arrival first.
    ///
    /// Home does not draw this; the search screen does, per `navigation-shell`'s *What search
    /// opens onto*. It lives here rather than there because the question is *what reading
    /// state is this publication in*, and that question is answered in exactly one place in
    /// this codebase — see ``isUnread(_:_:)``, and see ``upNext(in:limit:progress:)`` for
    /// what a second answer to a question like this costs.
    ///
    /// Newest first for the same reason ``recentlyAdded(in:limit:)`` is: of all the books a
    /// reader has not read, the ones they just added are the ones they were thinking about.
    /// Undated arrivals keep the library's own order rather than being dropped — a folder
    /// copied wholesale reports nothing, and a section that emptied itself over that would
    /// take the offer away from the reader who most needs it.
    static func neverOpened(
        in library: [Publication],
        limit: Int = shelfLength,
        progress: (Publication) -> ReadingProgress?
    ) -> [Publication] {
        library
            .filter { isUnread($0, progress) }
            .sorted { arrived($0) > arrived($1) }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Reading states

    /// Part-way through: opened, moved, not finished.
    private static func isPartRead(
        _ publication: Publication,
        _ progress: (Publication) -> ReadingProgress?
    ) -> Bool {
        LibraryIndex.Progress.of(progress(publication)).state == .inProgress
    }

    /// Never opened, or opened and never moved.
    private static func isUnread(
        _ publication: Publication,
        _ progress: (Publication) -> ReadingProgress?
    ) -> Bool {
        LibraryIndex.Progress.of(progress(publication)).state == .unread
    }
}
