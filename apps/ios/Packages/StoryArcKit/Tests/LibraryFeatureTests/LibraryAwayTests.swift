import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// Which sentence a reader gets when the shelf is bare and sources are configured.
///
/// The branch is the whole substance of ``LibraryAway``: *none of the places you added can
/// be reached* and *nothing has arrived from them yet* are two different claims, one about
/// the network and one about the books, and showing the wrong one tells a reader something
/// untrue about their own device. A screenshot proves the layout; only this proves the
/// choice.
///
/// It also pins the reason the predicate is not simply "no publications": a local folder is
/// marked `connected` when it is added, so a reader whose only source is an empty folder is
/// not offline — they have an empty folder.
///
/// Android asserts the same rule in `LibraryAwayTest`.
@Suite("Library away state")
struct LibraryAwayTests {

    private func source(
        _ name: String,
        kind: SourceKind = .opdsCatalog,
        state: SourceConnectionState
    ) -> Source {
        Source(displayName: name, kind: kind, state: state)
    }

    @Test("A registry with no sources is not away — it is unconfigured")
    func noSourcesIsNotAway() {
        // The first-run state, which is a different screen entirely: `sources` wants one
        // sentence and an offer to open a comic there, not a network complaint.
        #expect(LibraryAway.everythingAway(in: SourceRegistry()) == false)
    }

    @Test("Every source unreachable is away")
    func allUnreachableIsAway() {
        let registry = SourceRegistry(sources: [
            source("Home NAS", kind: .networkShare, state: .unreachable(since: .now)),
            source("Standard Ebooks", state: .unreachable(since: .now)),
        ])
        #expect(LibraryAway.everythingAway(in: registry))
    }

    @Test("One source still answering is not away, however many are not")
    func oneReachableIsNotAway() {
        let registry = SourceRegistry(sources: [
            source("Home NAS", kind: .networkShare, state: .unreachable(since: .now)),
            source("Standard Ebooks", state: .connected),
        ])
        // The reachable one has simply sent nothing yet. Telling this reader that nothing
        // can be reached would be a lie about their network.
        #expect(LibraryAway.everythingAway(in: registry) == false)
    }

    @Test("An empty local folder is not the network being away")
    func emptyFolderIsNotAway() {
        let registry = SourceRegistry(sources: [
            source("Comics", kind: .localFolder, state: .connected),
        ])
        #expect(LibraryAway.everythingAway(in: registry) == false)
    }

    @Test("A source still connecting counts as away, because it cannot serve anything yet")
    func connectingIsAway() {
        // `connecting` is not an error and is not drawn as one — but it cannot fetch, and
        // the honest offer while it cannot is the same one: ask again, or open a comic.
        let registry = SourceRegistry(sources: [source("Kavita", state: .connecting)])
        #expect(LibraryAway.everythingAway(in: registry))
    }

    @Test("An unauthorized source is away as well as needing action")
    func unauthorizedIsAway() {
        let registry = SourceRegistry(sources: [
            source("Kavita", state: .unauthorized(reason: "401")),
        ])
        #expect(LibraryAway.everythingAway(in: registry))
    }
}
