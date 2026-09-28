import Testing

@testable import ReaderFeature

/// The placeholder ratio for a page that has not decoded, from whichever page nearby
/// has. Android's `PagePlaceholderTest` asserts the same table.
@Suite("Page placeholder")
struct PagePlaceholderTests {

    @Test("Nothing decoded yet is the ordinary comic-page default")
    func nothingDecodedIsTheDefault() {
        #expect(PagePlaceholder.ratio(nearest: 5, among: [:]) == PagePlaceholder.defaultRatio)
    }

    @Test("The one decoded page nearby is used, however far off it reads")
    func oneDecodedPageWins() {
        #expect(PagePlaceholder.ratio(nearest: 5, among: [2: 0.4]) == 0.4)
    }

    @Test("The nearer of two decoded pages wins, whichever side it is on")
    func nearerPageWinsOnEitherSide() {
        let ratios = [0: 0.65, 10: 0.2]
        #expect(PagePlaceholder.ratio(nearest: 2, among: ratios) == 0.65)
        #expect(PagePlaceholder.ratio(nearest: 8, among: ratios) == 0.2)
    }

    @Test("Exactly between two, the lower index wins — a plain, stable tie-break")
    func tiedDistanceIsStable() {
        #expect(PagePlaceholder.ratio(nearest: 5, among: [0: 0.65, 10: 0.2]) == 0.65)
    }

    @Test("A page that is itself decoded is its own nearest")
    func decodedPageIsItsOwnNearest() {
        #expect(PagePlaceholder.ratio(nearest: 3, among: [3: 9.0, 4: 0.65]) == 9.0)
    }
}
