import Testing

@testable import LibraryFeature

/// Task 2.3 of `cover-for-every-publication`, as task 24.1 of `close-the-audited-gaps` changed
/// it: "the coverless well offers it".
///
/// The well used to be a button of its own that opened the picker. The cover's actions are one
/// menu now, so the well is that menu's label and no longer a second way in with one row.
/// Android's `CoverlessWellOffersAChoiceTest` presses the well under Robolectric, which is the
/// stronger reach; `CoverMenu.placement` is the decision both screens turn on here, and
/// `CoverMenuTests` reads the sources for the places that carry it out.
@Suite("The coverless well offers a choice")
struct CoverlessWellOffersAChoiceTests {

    private func menu(hasCover: Bool) -> CoverMenu {
        CoverMenu(
            hasCover: hasCover,
            rows: CoverMenu.rows(find: false, web: true, send: false, remove: false),
            act: { _ in }
        )
    }

    @Test("An empty well is the menu itself")
    func emptyWellIsTheMenu() {
        #expect(menu(hasCover: false).placement == .coverlessWell)
    }

    @Test("A publication that has artwork is looked at, and edited from its corner")
    func artworkHasAButtonOnItsCorner() {
        // Tapping a cover is how a reader looks at it, so the artwork itself is not the menu.
        #expect(menu(hasCover: true).placement == .buttonOnCover)
    }
}
