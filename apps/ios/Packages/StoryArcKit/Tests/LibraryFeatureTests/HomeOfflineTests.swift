import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// Home with every source down.
///
/// The design direction cites this as Plex's documented failure: watched state syncs across
/// servers but the Continue Watching row does not, so home becomes a union of libraries and
/// a *fragment* of the reader's own history. `home-screen` answers it with a requirement —
/// the surface renders "complete and immediately, with the same shelves in the same order as
/// when the sources are up", and what is not readable is dimmed rather than removed.
///
/// That is a promise about something not happening, which is the kind that rots quietly. So
/// it is asserted with every source marked unreachable, against the model the screen reads.
@Suite("Home with nothing reachable")
@MainActor
struct HomeOfflineTests {

    /// A library of three issues, one of them part-read, one of them finished.
    private func model(withEverythingUnreachable isDown: Bool) -> LibraryModel {
        let first = issue("Saga", "1")
        let second = issue("Saga", "2")
        let third = issue("Saga", "3")

        let model = LibraryModel()
        model.publications = [first, second, third]
        for publication in model.publications {
            model.locations[publication.id] = URL(filePath: "/library/\(publication.id).cbz")
        }
        model.progress = [
            first.id: finishedRecord(first),
            second.id: partReadRecord(second),
        ]

        if isDown {
            let server = Source(
                displayName: "Home NAS",
                kind: .networkShare,
                state: .unreachable(since: Date(timeIntervalSince1970: 1))
            )
            model.registry = SourceRegistry().adding(server)
        }

        model.rebuild()
        return model
    }

    private func issue(_ series: String, _ number: String) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/\(series)/\(number).cbz"),
            format: .cbz,
            displayTitle: "\(series) #\(number)",
            series: series,
            number: number,
            origin: .inferred
        )
    }

    private func partReadRecord(_ publication: Publication) -> ReadingProgress {
        ReadingProgress(
            identity: publication.identity,
            position: .page(index: 4, of: 20),
            updatedAt: Date(timeIntervalSince1970: 500)
        )
    }

    private func finishedRecord(_ publication: Publication) -> ReadingProgress {
        ReadingProgress(
            identity: publication.identity,
            position: .page(index: 19, of: 20),
            isFinished: true,
            finishedAt: Date(timeIntervalSince1970: 400),
            updatedAt: Date(timeIntervalSince1970: 400)
        )
    }

    @Test("The same shelves, in the same order, with every source unreachable")
    func shelvesDoNotDependOnASource() {
        let up = model(withEverythingUnreachable: false)
        let down = model(withEverythingUnreachable: true)

        #expect(up.continueReading.map(\.id) == down.continueReading.map(\.id))
        #expect(
            HomeShelves.upNext(in: up.publications) { up.record(of: $0) }.map(\.id)
                == HomeShelves.upNext(in: down.publications) { down.record(of: $0) }.map(\.id)
        )
        #expect(
            HomeShelves.recentlyAdded(in: up.publications).map(\.id)
                == HomeShelves.recentlyAdded(in: down.publications).map(\.id)
        )
        #expect(
            HomeShelves.finished(in: up.publications) { up.record(of: $0) }
                == HomeShelves.finished(in: down.publications) { down.record(of: $0) }
        )
    }

    @Test("Keep reading is not empty when nothing can be reached")
    func keepReadingSurvives() {
        #expect(model(withEverythingUnreachable: true).continueReading.count == 1)
    }

    @Test("A publication the app cannot open stays on the shelf and is marked, not dropped")
    func unreadableStaysDimmed() throws {
        let model = model(withEverythingUnreachable: true)
        let publication = try #require(model.continueReading.first)

        // The bytes go away — the share unmounts, the card is pulled — and the row keeps
        // its length. That is the whole rule: dimmed, never dropped.
        model.locations.removeValue(forKey: publication.id)
        model.rebuild()

        #expect(model.continueReading.count == 1)
        #expect(model.isReadableNow(publication) == false)
    }

    @Test("A publication whose format cannot be decoded is never offered as readable")
    func refusedIsNotReadable() {
        let model = LibraryModel()
        let refused = Publication(
            identity: PublicationIdentity(normalizedPath: "/solid.cbr"),
            format: .cbr,
            displayTitle: "Solid archive",
            origin: .inferred,
            streaming: .refused
        )
        model.publications = [refused]
        model.locations[refused.id] = URL(filePath: "/solid.cbr")

        #expect(model.isReadableNow(refused) == false)
    }

    @Test("No shelf appears, reorders or grows when a slow source answers")
    func slowSourcesChangeNothing() throws {
        // `home-screen`: no shelf "appears, reorders or grows once" a source answers. Until
        // 2026-09-05 this clause was asserted nowhere on either platform — it was argued in
        // a doc comment and by the shape of the code, which is exactly the kind of proof a
        // test replaces.
        //
        // Three points along one source coming back: down, connecting, connected. The
        // shelves are a function of the library and the reading record, so if a source's
        // state could reach one, these three would differ. Reachability decides a *dim*,
        // never a membership and never an order.
        func shape(_ model: LibraryModel) -> [String] {
            model.continueReading.map { "keep:\($0.id)" }
                + HomeShelves.upNext(in: model.publications) { model.record(of: $0) }
                    .map { "next:\($0.id)" }
                + HomeShelves.recentlyAdded(in: model.publications).map { "recent:\($0.id)" }
                + HomeShelves.finished(in: model.publications) { model.record(of: $0) }
                    .flatMap { group in group.publications.map { "done:\(group.id):\($0.id)" } }
        }

        let server = Source(displayName: "Home NAS", kind: .networkShare)
        let down = attributed(to: server, state: .unreachable(since: Date(timeIntervalSince1970: 1)))
        let answering = attributed(to: server, state: .connecting)
        let up = attributed(to: server, state: .connected)

        // The input really does vary — three different registries, three different states —
        // which is what the suite's own `model(withEverythingUnreachable:)` cannot show,
        // because it attributes nothing to the source it configures.
        #expect(down.registry.sources.first?.state != up.registry.sources.first?.state)
        #expect(answering.registry.sources.first?.state == .connecting)

        // And the verdict does not move with it, which on iOS is true for a stronger reason
        // than the requirement asks: ``LibraryModel/isReadableNow(_:)`` is
        // `publication.isOpenable && location(of:) != nil` and **never reads the registry at
        // all**. A publication with no file of its own is dimmed whatever its library is
        // doing, and one with a file is offered whatever its library is doing.
        //
        // Android's `isReadableOffline` *does* branch on the source, so its half of this
        // clause is asserted differently — `HomeOfflineTest` varies readability directly.
        // Both platforms agree on what a reader sees; only one of them could have got here
        // by accident, and this is the one that could not.
        let away = try #require(down.publications.last)
        #expect(down.isReadableNow(away) == false)
        #expect(answering.isReadableNow(away) == false)
        #expect(up.isReadableNow(away) == false)

        #expect(shape(down) == shape(answering), "A shelf changed while a source was still answering.")
        #expect(shape(answering) == shape(up), "A shelf changed when the source finished answering.")
    }

    /// The same three issues, **attributed to one source**, with the third held only by that
    /// source so its state is the only thing that can decide whether it is readable.
    private func attributed(to source: Source, state: SourceConnectionState) -> LibraryModel {
        var configured = source
        configured.state = state

        let model = LibraryModel()
        model.publications = ["1", "2", "3"].map { number in
            var publication = issue("Saga", number)
            publication.sourceID = configured.id
            return publication
        }
        // The first two have local files; the third does not, so only the source can answer
        // for it.
        for publication in model.publications.prefix(2) {
            model.locations[publication.id] = URL(filePath: "/library/\(publication.id).cbz")
        }
        model.progress = [
            model.publications[0].id: finishedRecord(model.publications[0]),
            model.publications[1].id: partReadRecord(model.publications[1])
        ]
        model.registry = SourceRegistry().adding(configured)
        model.rebuild()
        return model
    }
}
