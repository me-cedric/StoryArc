import Formats
@testable import LibraryFeature
import SwiftUI
import XCTest

@MainActor
final class LibraryCatalogueTests: XCTestCase {
    func testCatalogue01HomeWithContent() {
        // 98 per cent: the glass edge of the two Resume capsules draws in one of two ways from run
        // to run, and the two differ in 1.3 per cent of the pixels.
        assertCatalogue("01-home-with-content", delay: 1.5, precision: 0.98) {
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

    func testCatalogue18LibrarySkippedNotice() {
        let one = SkippedPublications.Entry(name: "Broken Transfer.cbz", reason: .archiveUnreadable)
        assertCatalogue("18-library-skipped-notice", delay: 1.5) {
            LibraryView(model: CatalogueLibrary.model(skipped: [one]))
        }
    }

    func testCatalogue17LibraryAToZRail() {
        assertCatalogue("17-library-a-to-z-rail", delay: 1.5) {
            LibraryView(model: CatalogueLibrary.model(entries: CatalogueLibrary.alphabet))
        }
    }
}
