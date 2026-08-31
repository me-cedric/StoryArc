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
/// source looks right whether the set is fixed at four or happens to be four today.
///
/// Android's own destination type asserts the same four in the same order.
@Suite("Library destinations")
struct LibraryDestinationTests {

    private func source(_ name: String, _ kind: SourceKind) -> Source {
        Source(displayName: name, kind: kind)
    }

    @Test("Four destinations, in the order a reader meets them")
    func fourInOrder() {
        #expect(LibraryDestination.allCases == [.home, .library, .onDevice, .search])
    }

    @Test("A reader who has added nothing gets all four")
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
    func manySourcesAreStillFourDestinations() {
        // The old sidebar grew a row per browsable source, so nine servers was eleven
        // rows — over Material's ceiling on the mirrored side, and a reader's own
        // navigation reading back the transports their books arrived over.
        //
        // Four is still inside Material's range on the mirrored side — 3–5 for the
        // navigation bar, 3–7 for the collapsed rail — so the fourth destination costs
        // nothing here. A tenth server would have.
        let sources = (1...9).map { source("Server \($0)", .kavitaServer) }
        #expect(LibraryDestination.all(for: sources).count == 4)
    }

    @Test("Every destination is drawn with a symbol of its own")
    func symbolsAreDistinct() {
        let symbols = LibraryDestination.allCases.map(\.symbolName)
        #expect(Set(symbols).count == LibraryDestination.allCases.count)
        #expect(symbols.allSatisfy { !$0.isEmpty })
    }

    @Test("Search is a destination, and a source is still not one")
    func searchIsADestinationAndSourcesAreNot() {
        // **This assertion is inverted from the one it replaces, and the old one is the
        // reason.** It read: "Search is not a destination — it is the platform's own role,
        // `Tab(role: .search)` on iOS, a field at the top of the surface on Android — set
        // apart from the destinations rather than listed among them. A fourth case here is
        // how it would end up listed among them." That argument was about *listing*, and it
        // was answered by the wrong control: the role does not merely sit apart, it morphs
        // the tab into a field in place, so the bar changes shape under the reader's thumb
        // and there is nowhere to land. `navigation-shell` now forbids exactly that.
        //
        // What the old assertion was protecting is still protected, by the two cases above:
        // the set does not grow when a reader configures a source. Search is in the set
        // because the app puts it there, once, not because anything was added.
        #expect(LibraryDestination.allCases.contains(.search))
        #expect(LibraryDestination.allCases.count == 4)

        let sources = SourceKind.allCases.map { source("A \($0.rawValue)", $0) }
        #expect(LibraryDestination.all(for: sources).count == 4)
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
