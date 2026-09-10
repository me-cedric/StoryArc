import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// Which sources earn a way to the rest of what they hold.
///
/// `library-browsing`: what a source holds beyond what the app has read is "reachable from
/// search and from an explicit *more from this library* affordance at the foot of the
/// shelf". Search is asserted in `SearchListingTests`; this is the affordance.
///
/// **An affordance that is always there says nothing.** A shelf where every source gave
/// everything draws no footer, because a reader who meets the same line under every
/// library learns to skim past it — including on the day it means something.
///
/// Android's `MoreFromTheLibraryTest` asserts the same five cases.
@Suite("More from this library")
struct MoreFromTheLibraryTests {

    private func source(_ kind: SourceKind, id: UUID = UUID()) -> Source {
        Source(id: id, displayName: "\(kind)", kind: kind, locator: "https://x.invalid")
    }

    private func more(_ sources: [Source], partial: Set<UUID>) -> [Source] {
        sourcesWithMore(sources) { partial.contains($0) }
    }

    @Test("A server that held something back gets a way in")
    func aPartialServer() {
        let server = source(.kavitaServer)

        #expect(more([server], partial: [server.id]) == [server])
    }

    @Test("A source that gave everything does not")
    func aWholeSource() {
        #expect(more([source(.kavitaServer)], partial: []).isEmpty)
    }

    @Test("A local folder never does, however much of it was read")
    func aFolder() {
        // A folder is walked by this app, and a way into one leads back to the grid the
        // reader is already looking at. `SourceKind.hasItsOwnBrowser` is the same rule.
        let folder = source(.localFolder)

        #expect(more([folder], partial: [folder.id]).isEmpty)
    }

    @Test("Each kind with a browser of its own is offered")
    func everyBrowsableKind() {
        let sources = [source(.kavitaServer), source(.opdsCatalog), source(.networkShare)]

        #expect(more(sources, partial: Set(sources.map(\.id))) == sources)
    }

    @Test("Only the sources that held something back, in the order the registry has them")
    func inRegistryOrder() {
        let first = source(.kavitaServer)
        let second = source(.opdsCatalog)
        let third = source(.networkShare)

        #expect(more([first, second, third], partial: [first.id, third.id]) == [first, third])
    }
}
