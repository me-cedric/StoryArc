import Foundation
import StoryArcCore
import Testing

@testable import Persistence

/// ADR-0006's first identity rule, built from what the browser already knows.
///
/// The browser holds a library, a series, a volume and a chapter for every chapter it opens.
/// Only two of those name the publication: the server it came from and the chapter itself.
/// Android's `KavitaOriginIdentityTest` asserts the same cases.
@Suite("A Kavita origin as a publication identity")
struct KavitaOriginIdentityTests {

    private func origin(sourceId: String, chapterId: Int = 42) -> KavitaOrigin {
        KavitaOrigin(
            sourceId: sourceId,
            libraryId: 1,
            seriesId: 7,
            volumeId: 3,
            chapterId: chapterId
        )
    }

    @Test("A chapter on a source the app knows becomes a server identifier")
    func aKnownSourceYieldsAnIdentifier() {
        let source = UUID()

        #expect(
            origin(sourceId: source.uuidString).serverIdentifier
                == PublicationIdentity.ServerIdentifier(sourceID: source, remoteID: "42")
        )
    }

    @Test("A source id that is not an identifier yields nothing at all")
    func anUnparsableSourceYieldsNothing() {
        // Nothing is invented here. The store keys a server identity by the source's own
        // id, and a guessed one would file two servers as one publication — data loss in
        // the one store this app promises never to lose.
        #expect(origin(sourceId: "not-a-uuid").serverIdentifier == nil)
        #expect(origin(sourceId: "").serverIdentifier == nil)
    }

    @Test("Two chapters on one server are two publications")
    func chaptersAreDistinct() {
        let source = UUID().uuidString

        #expect(
            origin(sourceId: source, chapterId: 7).serverIdentifier
                != origin(sourceId: source, chapterId: 8).serverIdentifier
        )
    }

    @Test("The same chapter number on two servers is two publications")
    func serversAreDistinct() {
        // Kavita numbers chapters per server. Two readers' servers both have a chapter 42
        // and they are different books.
        #expect(
            origin(sourceId: UUID().uuidString).serverIdentifier
                != origin(sourceId: UUID().uuidString).serverIdentifier
        )
    }
}
