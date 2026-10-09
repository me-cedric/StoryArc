@testable import LibraryFeature
import SwiftUI
import XCTest

@MainActor
final class LibraryCatalogueTests: XCTestCase {
    func testCatalogue01HomeWithContent() {
        assertCatalogue("01-home-with-content", delay: 1.5) {
            HomeScreen(model: CatalogueLibrary.model())
        }
    }

    func testCatalogue02HomeFirstRun() {
        assertCatalogue("02-home-first-run", delay: 1.0) {
            HomeScreen(model: CatalogueLibrary.model(entries: []))
        }
    }

    func testCatalogue03LibraryGrid() {
        assertCatalogue("03-library-grid", delay: 1.5) {
            LibraryView(model: CatalogueLibrary.model())
        }
    }

    func testCatalogue04LibraryList() {
        assertCatalogue("04-library-list", delay: 1.5) {
            LibraryView(model: CatalogueLibrary.model(layout: .list))
        }
    }

    func testCatalogue14SearchAtRest() {
        assertCatalogue("14-search-at-rest", delay: 1.5) {
            LibraryView(model: CatalogueLibrary.model(), surface: .search)
        }
    }

    func testCatalogue17LibraryAToZRail() {
        assertCatalogue("17-library-a-to-z-rail", delay: 1.5) {
            LibraryView(model: CatalogueLibrary.model(entries: CatalogueLibrary.alphabet))
        }
    }
}
