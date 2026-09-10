import Foundation

/// What a server's `pagesRead` and `pagesTotal` say about one entry of a reading list.
///
/// Kept apart from the row that draws it so the rule can be asserted without a view, and so
/// both platforms state it the same way. Android's `ServerListProgress` is its twin.
///
/// The distinction that matters is ``State/unknown`` against ``State/unread``. Kavita sends
/// `pagesRead: 0` for both an unread entry and an entry it has no page count for, and
/// `collections-and-reading-lists` asks for nothing to be claimed in the second case: "the
/// entry states nothing rather than an assumed zero, and the list's own count of finished
/// entries excludes it rather than counting it unread". A total of zero is the only honest
/// signal of the difference.
enum ServerListProgress {

    /// How far into an entry a reader has gone, as the server reports it.
    enum State: Equatable, Sendable {
        /// The server gave no page count, so nothing is known and nothing is said.
        case unknown
        /// A known length, none of it read.
        case unread
        /// Part of a known length, at `percent` of the way through.
        case part(percent: Int)
        /// Every page of a known length, or more.
        case finished
    }

    /// How many of a list's entries are finished, out of the ones it knows about.
    struct Counted: Equatable, Sendable {
        let finished: Int
        let of: Int
    }

    static func of(pagesRead: Int, pagesTotal: Int) -> State {
        guard pagesTotal > 0 else { return .unknown }
        guard pagesRead > 0 else { return .unread }
        guard pagesRead < pagesTotal else { return .finished }
        // Clamped away from both ends: one page of four hundred is progress a reader made
        // and 0% would deny it, and a page short of the end is not finished.
        return .part(percent: min(99, max(1, pagesRead * 100 / pagesTotal)))
    }

    /// The list's own tally, or nil when the server said nothing about any entry.
    static func summary(_ entries: [(read: Int, total: Int)]) -> Counted? {
        let known = entries
            .map { of(pagesRead: $0.read, pagesTotal: $0.total) }
            .filter { $0 != .unknown }
        guard !known.isEmpty else { return nil }
        return Counted(finished: known.filter { $0 == .finished }.count, of: known.count)
    }
}
