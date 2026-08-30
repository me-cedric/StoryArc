import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// What a wide window's sidebar offers.
///
/// `native-experience` asks a large screen for "a multi-column layout with a persistent
/// sidebar". What goes in it is the part that can be wrong without anyone noticing on a
/// screenshot — an order that shuffles when a source is added, a folder that appears as a
/// destination and leads back to the grid it came from, a collections row that goes
/// missing when the registry is empty.
///
/// Android's `SidebarDestinationTest` asserts the same list in the same order.
@Suite("Library sidebar")
struct LibrarySidebarTests {

    private func source(_ name: String, _ kind: SourceKind) -> Source {
        Source(displayName: name, kind: kind)
    }

    @Test("An empty registry still offers the library and the collections")
    func emptyRegistry() {
        // A reader who has added nothing still has shelves, and still needs somewhere to
        // stand. A sidebar that was empty until a server was added would be a sidebar
        // that looked broken on first launch.
        #expect(SidebarDestination.all(for: []) == [.library, .shelves])
    }

    @Test("A local folder is not a destination")
    func foldersAreNotDestinations() {
        // Its publications were scanned into the grid, so a row for it would lead back to
        // the row above it.
        let folder = source("Comics", .localFolder)
        #expect(SidebarDestination.all(for: [folder]) == [.library, .shelves])
    }

    @Test("Every browsable source gets a row, in registry order")
    func browsableSourcesAreListed() {
        let catalogue = source("Standard Ebooks", .opdsCatalog)
        let server = source("Kavita", .kavitaServer)
        let share = source("NAS", .networkShare)
        let folder = source("Comics", .localFolder)

        // The folder sits in the middle of the registry on purpose: filtering it out must
        // not disturb the order of the three that stay.
        let destinations = SidebarDestination.all(for: [catalogue, folder, server, share])
        #expect(
            destinations == [
                .library,
                .source(catalogue.id),
                .source(server.id),
                .source(share.id),
                .shelves,
            ]
        )
    }

    @Test("The library is first and the collections last, whatever is between them")
    func libraryFirstShelvesLast() {
        let sources = (1...5).map { source("Server \($0)", .kavitaServer) }
        let destinations = SidebarDestination.all(for: sources)
        #expect(destinations.first == .library)
        #expect(destinations.last == .shelves)
        #expect(destinations.count == sources.count + 2)
    }

    @Test("The sidebar lists exactly the sources the narrow window's strip does")
    func sameSetAsTheCatalogueStrip() {
        // The two are the same set on purpose: the wide window shows the destinations a
        // narrow one keeps in a horizontal strip, and a reader who resizes should find
        // the same places, not a different set with the same name.
        let sources = SourceKind.allCases.map { source("A \($0.rawValue)", $0) }
        let inStrip = sources.filter { $0.kind.isBrowsable }.map { SidebarDestination.source($0.id) }
        let inSidebar = SidebarDestination.all(for: sources).filter {
            if case .source = $0 { return true }
            return false
        }
        #expect(inSidebar == inStrip)
    }
}

/// Which source kinds are a place to travel to.
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
