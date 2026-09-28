internal import Foundation

/// Where a source's continued read stands: how much of it has been merged so far, how much
/// more there is when the count is known, and which page answers next.
///
/// `sources`' *More from a source than the library holds*: the first read is a slice, and
/// this is what a source keeps between the page that finished it and the page that
/// continues it — across a pull that starts a second `readServers()` before the first has
/// finished, and across the source going unreachable and coming back. Android's
/// `SourceReadProgress` is the same shape.
struct SourceReadProgress: Equatable {
    /// Merged so far. Seeded from the first slice, which the source detail screen already
    /// counted before any of this existed.
    var read: Int
    /// The server's whole count, once it is known. `nil` reads as "holds more" with no
    /// number, which is every source kind's behaviour before this and every kind this does
    /// not yet know a total for.
    var total: Int?
    /// The next page to ask for.
    var nextPage: Int

    static func started(firstSliceRead: Int) -> SourceReadProgress {
        SourceReadProgress(read: firstSliceRead, total: nil, nextPage: 2)
    }
}

/// What one more page does to a source's progress.
enum SourceReadStep: Equatable {
    /// The page asked for is not the page this progress is waiting on — a second reader of
    /// the same source already moved past it, most often two `readServers()` calls
    /// overlapping. Folding this answer in as well would count that page twice.
    case stale
    /// The server has more after this page.
    case continuing(SourceReadProgress)
    /// This page was short (or empty): the read reached the end.
    case finished(SourceReadProgress)
}

extension SourceReadProgress {
    /// Folds one page's answer into this progress.
    ///
    /// A free function beside the type rather than logic inside the async loop that calls
    /// it, so a network-less test suite can assert every one of its three answers directly.
    /// `SourceReadProgressTests` is that reach.
    func advancing(pageRequested: Int, unitsRead: Int, holdsMore: Bool) -> SourceReadStep {
        guard pageRequested == nextPage else { return .stale }
        let merged = SourceReadProgress(read: read + unitsRead, total: total, nextPage: nextPage + 1)
        return holdsMore ? .continuing(merged) : .finished(merged)
    }
}
