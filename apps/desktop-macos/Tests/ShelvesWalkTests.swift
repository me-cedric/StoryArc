import AppKit
import Foundation
import StoryArcCore
import Testing

@testable import StoryArc

extension WindowWalks {
    /// Task 3.15a's walk: a shelf made, filled, found in the sidebar and on Home, opened, then
    /// deleted with its books left where they were.
    @MainActor
    @Suite("Shelves walk")
    struct ShelvesWalkTests {
        @Test("A collection is made, filled, seen on Home and in the sidebar, and deleted with the books kept")
        func collection() async throws {
            let library = try await Walk.fixtureLibrary()
            let first = try #require(Walk.publication(named: "natural-sort", in: library))
            let second = try #require(Walk.publication(named: "image-pages", in: library))
            let pin = try #require(library.createShelf(.collection, named: "Walk Shelf", with: [first.id, second.id]))
            var deleted = false
            defer { if !deleted { Task { await library.deleteShelf(pin) } } }

            let row = try #require(library.shelfRows.first { $0.pin == pin })
            #expect(row.count == 2)
            #expect(MacShelves.home(library.model.shelves, pins: ShelfPins.shared.pins).collections.contains(row))

            // Home draws it: the card is a control VoiceOver reads by the shelf's name.
            // Searched clear and taken home the way the catalogue asks, since an earlier walk can
            // leave a search or a pushed page; and every visible window is read, since the shell
            // walk before this one can leave a second library window in front.
            let window = try #require(ShellWalk.waitForLibraryWindow())
            window.makeKeyAndOrderFront(nil)
            for request in [LibraryNavigation.search(""), .root, .go(.home)] {
                library.navigationRequest = request
                _ = await Walk.until(.seconds(4)) { library.navigationRequest == nil ? true : nil }
            }
            let card = await Walk.until(.seconds(15)) {
                ShellWalk.visibleWindows().lazy
                    .flatMap { AccessibilityAudit.controls(in: $0) }
                    .first { $0.name.hasPrefix("Walk Shelf") }
            }
            #expect(card != nil, "Home did not show the shelf")
            ConformanceLog.note("shelf on Home", card.map { "\($0.role) “\($0.name)”" } ?? "absent")

            // Its page lists both, and a bulk mark reaches both.
            library.navigationRequest = .shelf(pin)
            _ = await Walk.until { library.navigationRequest == nil ? true : nil }
            let members = MacShelves.members(of: pin, in: library.model.shelves, library: library.model.publications)
            #expect(Set(members.map(\.id)) == [first.id, second.id])
            await library.mark([first.id, second.id], read: true)
            #expect(library.record(of: first)?.isFinished == true)
            await library.mark([first.id, second.id], read: false)

            await library.deleteShelf(pin)
            deleted = true
            #expect(!library.shelfRows.contains { $0.pin == pin })
            #expect(Walk.publication(named: "natural-sort", in: library) != nil, "deleting the shelf took a book")
            library.navigationRequest = .go(.home)
        }

        @Test("A reading list keeps the order its entries were added in, and moves one by hand")
        func readingList() async throws {
            let library = try await Walk.fixtureLibrary()
            let names = ["zip64", "natural-sort", "image-pages"]
            let ids = try names.map { try #require(Walk.publication(named: $0, in: library)).id }
            let pin = try #require(library.createShelf(.list, named: "Walk List", with: ids))
            defer { Task { await library.deleteShelf(pin) } }
            guard case let .list(listID) = pin else { throw WalkFailure("not a list") }
            let order = {
                MacShelves.entries(
                    of: listID, in: library.model.shelves, library: library.model.publications, pending: []
                ).map(\.id)
            }
            #expect(order() == ids)
            library.move(ids[2], to: 0, inList: listID)
            #expect(order() == [ids[2], ids[0], ids[1]])
            let home = MacShelves.home(library.model.shelves, pins: ShelfPins.shared.pins)
            #expect(home.lists.contains { $0.pin == pin }, "Home lacks the reading list")
        }
    }
}
