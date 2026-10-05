import StoryArcCore
import Testing

@testable import LibraryFeature

/// The continuation loop a network share and an OPDS catalogue share, with the cursor a
/// folder-queue list rather than a page number — ``readSourceOnward`` is a page table and
/// one progress value standing in for either source. `KavitaContinuedReadTests` asks the
/// same four questions of ``readOnward(progress:fetch:land:)``.
@MainActor
struct ContinuedReadLoopTests {

    private func slice(_ found: Int, holdsMore: Bool) -> SourceSlice {
        SourceSlice(publications: (0..<found).map { _ in fakePublication() }, holdsMore: holdsMore)
    }

    private func fakePublication() -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "x"),
            format: .cbz,
            displayTitle: "x",
            origin: .inferred
        )
    }

    private final class Reader {
        var progress: SourceReadProgress?
        var cursor: Int
        var landed: [SourceReadStep] = []

        init(_ progress: SourceReadProgress?, cursor: Int) {
            self.progress = progress
            self.cursor = cursor
        }

        func land(_ step: SourceReadStep) {
            landed.append(step)
            if case .continuing(let next) = step { progress = next } else { progress = nil }
        }
    }

    @Test("A read goes on cursor by cursor until a short page ends it")
    func readsToTheEnd() async {
        let reader = Reader(SourceReadProgress(read: 60, total: nil, nextPage: 2), cursor: 1)
        var asked: [Int] = []
        let pages: [Int: (SourceSlice, Int)] = [1: (slice(60, holdsMore: true), 2), 2: (slice(34, holdsMore: false), 3)]

        await readSourceOnward(
            progress: { reader.progress },
            cursor: { reader.cursor },
            fetch: { asked.append($0); return pages[$0] },
            advance: { reader.cursor = $0 },
            land: { _, step in reader.land(step) }
        )

        #expect(asked == [1, 2])
        #expect(reader.landed == [
            .continuing(SourceReadProgress(read: 120, total: nil, nextPage: 3)),
            .finished(SourceReadProgress(read: 154, total: nil, nextPage: 4)),
        ])
        #expect(reader.progress == nil)
    }

    @Test("A refused page leaves the read where it stood")
    func refusedPageStops() async {
        let reader = Reader(SourceReadProgress(read: 60, total: nil, nextPage: 2), cursor: 1)
        let pages: [Int: (SourceSlice, Int)] = [1: (slice(60, holdsMore: true), 2)]

        await readSourceOnward(
            progress: { reader.progress },
            cursor: { reader.cursor },
            fetch: { pages[$0] },
            advance: { reader.cursor = $0 },
            land: { _, step in reader.land(step) }
        )

        #expect(reader.progress == SourceReadProgress(read: 120, total: nil, nextPage: 3))
    }

    @Test("An answer for a page another reader already folded in is dropped")
    func overlappingAnswerIsDropped() async {
        let reader = Reader(SourceReadProgress(read: 60, total: nil, nextPage: 2), cursor: 1)
        let alreadyFolded = SourceReadProgress(read: 120, total: nil, nextPage: 3)

        await readSourceOnward(
            progress: { reader.progress },
            cursor: { reader.cursor },
            fetch: { requested in
                guard requested == 1 else { return nil }
                reader.progress = alreadyFolded
                return (slice(60, holdsMore: true), 2)
            },
            advance: { reader.cursor = $0 },
            land: { _, step in reader.land(step) }
        )

        #expect(reader.landed.isEmpty)
        #expect(reader.progress == alreadyFolded)
    }

    @Test("A read another reader finished is not opened again")
    func finishedReadStaysFinished() async {
        let reader = Reader(SourceReadProgress(read: 120, total: nil, nextPage: 3), cursor: 2)

        await readSourceOnward(
            progress: { reader.progress },
            cursor: { reader.cursor },
            fetch: { requested in
                guard requested == 2 else { return nil }
                reader.progress = nil
                return (slice(60, holdsMore: true), 3)
            },
            advance: { reader.cursor = $0 },
            land: { _, step in reader.land(step) }
        )

        #expect(reader.landed.isEmpty)
        #expect(reader.progress == nil)
    }
}
