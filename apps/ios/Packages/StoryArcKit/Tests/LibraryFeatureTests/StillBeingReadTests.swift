import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// Which sources the shelf says it is still reading.
///
/// A reader adds a Kavita server, opens the library and sees the shelf they already had.
/// The client waits twenty seconds before giving up, so for twenty seconds the app is
/// indistinguishable from one that ignored the source.
///
/// **The three cases that must not be counted are the point of the test.** A source that
/// answered and holds nothing is not waiting; one that is unreachable is a different
/// sentence, already carried elsewhere; and a local folder is walked by this app, with its
/// own indicator. A notice that is usually wrong is a notice a reader learns to ignore.
///
/// Android's `StillBeingReadTest` asserts the same six cases.
@Suite("What the shelf is still reading")
struct StillBeingReadTests {

    private func source(
        kind: SourceKind = .kavitaServer,
        state: SourceConnectionState = .connecting,
        id: UUID = UUID()
    ) -> Source {
        Source(id: id, displayName: "A place", kind: kind, state: state, locator: "https://x.invalid")
    }

    private func row(sourceID: UUID?) -> Publication {
        Publication(
            identity: PublicationIdentity(contentDigest: UUID().uuidString),
            format: .cbz,
            displayTitle: "Something",
            origin: .inferred,
            sourceID: sourceID
        )
    }

    @Test("A server still being asked, with nothing on the shelf, is being read")
    func waiting() {
        #expect(sourcesStillBeingRead(sources: [source()], publications: []) == 1)
    }

    @Test("A server that has put something on the shelf is not still being read")
    func answered() {
        let server = source()
        #expect(sourcesStillBeingRead(sources: [server], publications: [row(sourceID: server.id)]) == 0)
    }

    @Test("A server that answered and holds nothing says nothing")
    func emptyButConnected() {
        // The case that would make this notice a liar. A connected server with an empty
        // library is not waiting, and a line that stayed up for ever is one a reader learns
        // to ignore — including on the day it is true.
        #expect(sourcesStillBeingRead(sources: [source(state: .connected)], publications: []) == 0)
    }

    @Test("An unreachable server is a different sentence, so it is not this one")
    func unreachable() {
        let away = source(state: .unreachable(since: .distantPast))
        #expect(sourcesStillBeingRead(sources: [away], publications: []) == 0)
    }

    @Test("A local folder is never counted, because the scan says so itself")
    func aFolder() {
        #expect(sourcesStillBeingRead(sources: [source(kind: .localFolder)], publications: []) == 0)
    }

    @Test("Two servers waiting are two, and one of them answering leaves one")
    func two() {
        let first = source()
        let second = source()

        #expect(sourcesStillBeingRead(sources: [first, second], publications: []) == 2)
        #expect(
            sourcesStillBeingRead(sources: [first, second], publications: [row(sourceID: first.id)]) == 1
        )
    }
}
