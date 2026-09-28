import Testing

@testable import LibraryFeature

/// The continuation loop itself: which pages it asks for, which answers it folds in, and
/// where it stops.
///
/// `sources`' *More from a source than the library holds*: "stop and resume cleanly when the
/// source becomes unreachable". ``readOnward(progress:fetch:land:)`` is the loop
/// `continueReadingKavita` runs, with the server and the model replaced by a page table and
/// one progress value. Android's `KavitaContinuedReadTest` asks the same four questions.
@MainActor
struct KavitaContinuedReadTests {

    private func page(_ series: Int, holdsMore: Bool) -> KavitaContributor.Page {
        KavitaContributor.Page(
            slice: SourceSlice(publications: [], holdsMore: holdsMore),
            seriesRead: series
        )
    }

    /// One source's progress, and a record of every page the loop folded in.
    private final class Reader {
        var progress: SourceReadProgress?
        var landed: [SourceReadStep] = []

        init(_ progress: SourceReadProgress?) { self.progress = progress }

        func land(_ step: SourceReadStep) {
            landed.append(step)
            if case .continuing(let next) = step { progress = next } else { progress = nil }
        }
    }

    @Test("A read goes on page by page until a short page ends it")
    func readsToTheEnd() async {
        let reader = Reader(SourceReadProgress(read: 60, total: 154, nextPage: 2))
        var asked: [Int] = []
        let pages = [2: page(60, holdsMore: true), 3: page(34, holdsMore: false)]

        await readOnward(
            progress: { reader.progress },
            fetch: { asked.append($0); return pages[$0] },
            land: { _, step in reader.land(step) }
        )

        #expect(asked == [2, 3])
        #expect(reader.landed == [
            .continuing(SourceReadProgress(read: 120, total: 154, nextPage: 3)),
            .finished(SourceReadProgress(read: 154, total: 154, nextPage: 4)),
        ])
        #expect(reader.progress == nil)
    }

    @Test("A refused page leaves the read where it stood")
    func refusedPageStops() async {
        let reader = Reader(SourceReadProgress(read: 60, total: 215, nextPage: 2))
        let pages = [2: page(60, holdsMore: true)]

        await readOnward(
            progress: { reader.progress },
            fetch: { pages[$0] },
            land: { _, step in reader.land(step) }
        )

        #expect(reader.progress == SourceReadProgress(read: 120, total: 215, nextPage: 3))
    }

    @Test("An answer for a page another reader already folded in is dropped")
    func overlappingAnswerIsDropped() async {
        // A pull-to-refresh starts a second reader while the first is waiting on page two.
        // The first one lands page two while the second is still waiting on it.
        let reader = Reader(SourceReadProgress(read: 60, total: 215, nextPage: 2))
        let alreadyFolded = SourceReadProgress(read: 120, total: 215, nextPage: 3)

        await readOnward(
            progress: { reader.progress },
            fetch: { requested in
                guard requested == 2 else { return nil }
                reader.progress = alreadyFolded
                return page(60, holdsMore: true)
            },
            land: { _, step in reader.land(step) }
        )

        #expect(reader.landed.isEmpty)
        #expect(reader.progress == alreadyFolded)
    }

    @Test("A read another reader finished is not opened again")
    func finishedReadStaysFinished() async {
        let reader = Reader(SourceReadProgress(read: 120, total: 154, nextPage: 3))

        await readOnward(
            progress: { reader.progress },
            fetch: { requested in
                guard requested == 3 else { return nil }
                reader.progress = nil
                return page(60, holdsMore: true)
            },
            land: { _, step in reader.land(step) }
        )

        #expect(reader.landed.isEmpty)
        #expect(reader.progress == nil)
    }
}
