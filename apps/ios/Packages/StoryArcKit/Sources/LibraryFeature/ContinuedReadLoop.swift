internal import Foundation

/// The continuation loop a network share and an OPDS catalogue share: ask for the next page
/// by its own cursor, fold its answer in, and stop at a short page, a refused page, or a page
/// another reader already took.
///
/// The twin of ``readOnward(progress:fetch:land:)``, generalised over a cursor `C` instead of
/// a page number — a share continues from the folder queue its last page left
/// (``SmbContributor/Page/queue``) and a catalogue from the feed link its last page named
/// (``OpdsContributor/Page/next``), and neither is "page 2" the way a Kavita request is.
/// ``SourceReadProgress/nextPage`` still counts rounds for the staleness check both loops
/// share; it is just not what either of these two asks a server for.
///
/// A free function beside the model rather than logic inside the task that calls it, so a
/// test can assert all four of its answers without a server — `ContinuedReadLoopTests` is
/// that reach, the same way `KavitaContinuedReadTests` reaches `readOnward`.
@MainActor
func readSourceOnward<C>(
    progress: () -> SourceReadProgress?,
    cursor: () -> C,
    fetch: (C) async -> (SourceSlice, C)?,
    advance: (C) -> Void,
    land: (SourceSlice, SourceReadStep) -> Void
) async {
    while let requested = progress()?.nextPage {
        guard let (slice, nextCursor) = await fetch(cursor()),
              let step = progress()?.advancing(
                  pageRequested: requested,
                  unitsRead: slice.publications.count,
                  holdsMore: slice.holdsMore
              )
        else { return }
        switch step {
        case .stale:
            return
        case .continuing:
            advance(nextCursor)
            land(slice, step)
        case .finished:
            advance(nextCursor)
            land(slice, step)
            return
        }
    }
}
