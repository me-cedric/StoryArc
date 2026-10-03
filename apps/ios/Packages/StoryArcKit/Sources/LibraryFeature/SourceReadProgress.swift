internal import Foundation
internal import Persistence

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

    /// Where a source's continuation resumes from: what ``SourceReadProgressStore`` already
    /// has for it, or a fresh start at its own first slice.
    ///
    /// `sources`' *More from a source than the library holds*: before this existed, a source
    /// new to this process always meant ``started(firstSliceRead:)``, because nothing kept
    /// a continuation's place anywhere but ``LibraryModel/partialSources``, in memory. A free
    /// function beside the type, so a test can prove it against an isolated store without a
    /// `LibraryModel` — `SourceReadProgressResumingTests` is that reach. Android's own
    /// `adoptPartialSources` makes the same choice, inline.
    static func resuming(
        from store: SourceReadProgressStore,
        source sourceID: UUID,
        firstSliceRead: Int
    ) -> SourceReadProgress {
        store.progress(for: sourceID).map { SourceReadProgress(read: $0.read, total: $0.total, nextPage: $0.nextPage) }
            ?? .started(firstSliceRead: firstSliceRead)
    }
}

/// ``SourceReadProgress`` as ``SourceReadProgressStore`` keeps it on disk.
extension SourceReadProgress {
    var stored: StoredSourceProgress { StoredSourceProgress(read: read, total: total, nextPage: nextPage) }
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

/// The continuation loop: ask for the next page, fold its answer in, and stop at a short
/// page, a refused page, or a page another reader already took.
///
/// The progress is read again after the page arrives, not carried across the wait. Two
/// readers of one source overlap whenever a `readServers()` starts while a continuation is
/// mid-page, and the second answer for the same page is stale only when it is compared with
/// the progress as it stands now. Compared with the progress it started from, it always
/// matched, so both readers folded every page in and a finished read could come back as
/// partial. A test reaches this through `fetch` and `land`, without a server. Android's
/// `readOnward` is the same loop.
@MainActor
func readOnward(
    progress: () -> SourceReadProgress?,
    fetch: (Int) async -> KavitaContributor.Page?,
    land: (KavitaContributor.Page, SourceReadStep) -> Void
) async {
    while let requested = progress()?.nextPage {
        guard let page = await fetch(requested),
              let step = progress()?.advancing(
                  pageRequested: requested,
                  unitsRead: page.seriesRead,
                  holdsMore: page.slice.holdsMore
              )
        else { return }
        switch step {
        case .stale:
            return
        case .continuing:
            land(page, step)
        case .finished:
            land(page, step)
            return
        }
    }
}
