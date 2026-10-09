import XCTest

/// Wave 5 frames of the library shelf: the by-library filter.
@MainActor
final class SweepWave5LibraryTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// `one-library-three-destinations` 3.2: Which library, one library chosen, Clear filters.
    func testCaptureByLibraryFilter() throws {
        try XCTSkipUnless(MockCatalogues.areRunning(), "The mock catalogues are not running.")
        let app = sweepLaunch(sources: Wave5.twoCatalogues)
        try showTheShelf(in: app)
        waitForTheShelfToSettle(in: app, within: 20)
        hold(4)
        try openFilterMenu(in: app)
        try XCTUnwrap(hittable("Which library", in: app)).tap()
        XCTAssertNotNil(hittable(MockCatalogues.loft, in: app), "The menu lists no second library.")
        hold(0.75)
        shutter(app, named: "filter-which-library")
        try XCTUnwrap(hittable(MockCatalogues.attic, in: app)).tap()
        let control = app.buttons.matching(NSPredicate(format: "label == %@", "Filter")).firstMatch
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        XCTAssertEqual(control.value as? String, "1 filter active")
        hold(2)
        shutter(app, named: "filtered-to-one-library")
        try openFilterMenu(in: app)
        if hittable("Clear filters", in: app, timeout: 2) == nil { app.swipeUp() }
        XCTAssertNotNil(hittable("Clear filters", in: app, timeout: 2), "No way out is offered.")
        hold(0.75)
        shutter(app, named: "clear-filters-offered")
    }

    /// `one-library-three-destinations` 2.1 / 3.2 item 12: Home with the shelf narrowed to one
    /// library. Keep reading still shows: the filter stops at the shelf. The hero is a local
    /// comic, so it belongs to neither catalogue.
    func testCaptureHomeFilteredToOneLibrary() throws {
        try XCTSkipUnless(MockCatalogues.areRunning(), "The mock catalogues are not running.")
        let app = sweepLaunch(sources: Wave5.twoCatalogues)
        try showTheShelf(in: app)
        waitForTheShelfToSettle(in: app, within: 20)
        hold(4)
        try openFilterMenu(in: app)
        try XCTUnwrap(hittable("Which library", in: app)).tap()
        try XCTUnwrap(hittable(MockCatalogues.attic, in: app)).tap()
        let control = app.buttons.matching(NSPredicate(format: "label == %@", "Filter")).firstMatch
        XCTAssertEqual(control.value as? String, "1 filter active")
        hold(1.5)
        try w5Tab("Home", in: app)
        hold(3)
        shutter(app, named: "home-shelf-filtered-keep-reading-present")
    }
}
