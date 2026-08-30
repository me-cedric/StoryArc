import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// Where the app can send a reader, and the promise that the list never grows.
///
/// This replaces `LibrarySidebarTests`, which asserted the opposite arrangement: *library
/// → one row per browsable source → shelves*, with a case proving the sidebar listed
/// exactly the same servers as the strip above the shelf. Both are gone, and the reason
/// they are gone is the requirement asserted here — `navigation-shell` says the
/// destination set does not change "in response to anything the reader configures".
///
/// It is the part that cannot be read off a screenshot. A screenshot of a reader with one
/// source looks right whether the set is fixed at three or happens to be three today.
///
/// Android's own destination type asserts the same three in the same order.
@Suite("Library destinations")
struct LibraryDestinationTests {

    private func source(_ name: String, _ kind: SourceKind) -> Source {
        Source(displayName: name, kind: kind)
    }

    @Test("Three destinations, in the order a reader meets them")
    func threeInOrder() {
        #expect(LibraryDestination.allCases == [.home, .library, .onDevice])
    }

    @Test("A reader who has added nothing gets all three")
    func emptyRegistry() {
        // A destination set that filled in as sources were added would be a navigation
        // control that looked broken on first launch — and the on-device destination is
        // exactly the one a reader with no server still needs.
        #expect(LibraryDestination.all(for: []) == LibraryDestination.allCases)
    }

    @Test("Adding sources of every kind changes nothing")
    func sourcesAreNotDestinations() {
        let sources = SourceKind.allCases.map { source("A \($0.rawValue)", $0) }
        #expect(LibraryDestination.all(for: sources) == LibraryDestination.allCases)
    }

    @Test("Nine servers do not put a navigation control over its ceiling")
    func manySourcesAreStillThreeDestinations() {
        // The old sidebar grew a row per browsable source, so nine servers was eleven
        // rows — over Material's ceiling on the mirrored side, and a reader's own
        // navigation reading back the transports their books arrived over.
        let sources = (1...9).map { source("Server \($0)", .kavitaServer) }
        #expect(LibraryDestination.all(for: sources).count == 3)
    }

    @Test("Every destination is drawn with a symbol of its own")
    func symbolsAreDistinct() {
        let symbols = LibraryDestination.allCases.map(\.symbolName)
        #expect(Set(symbols).count == LibraryDestination.allCases.count)
        #expect(symbols.allSatisfy { !$0.isEmpty })
    }

    @Test("Search is not a destination")
    func searchIsARole() {
        // It is the platform's own role — `Tab(role: .search)` on iOS, a field at the top
        // of the surface on Android — set apart from the destinations rather than listed
        // among them. A fourth case here is how it would end up listed among them.
        #expect(LibraryDestination.allCases.count == 3)
    }
}

/// Which source kinds are a place to travel to.
///
/// Kept from the sidebar suite. Nothing in primary navigation reads it any more, but the
/// answer still decides which sources a search can offer to look further afield in.
@Suite("Browsable sources")
struct BrowsableSourceTests {

    @Test("Only a local folder is not browsable")
    func onlyFoldersAreNotBrowsable() {
        #expect(SourceKind.localFolder.isBrowsable == false)
        #expect(SourceKind.opdsCatalog.isBrowsable)
        #expect(SourceKind.kavitaServer.isBrowsable)
        #expect(SourceKind.networkShare.isBrowsable)
    }

    @Test("Every kind answers, so a fifth one cannot slip through unanswered")
    func everyKindAnswers() {
        // `isBrowsable` is a `switch` over every case rather than a comparison against
        // one, so adding a kind is a compile error rather than a silent "yes".
        #expect(SourceKind.allCases.count == 4)
        #expect(SourceKind.allCases.filter(\.isBrowsable).count == 3)
    }
}
