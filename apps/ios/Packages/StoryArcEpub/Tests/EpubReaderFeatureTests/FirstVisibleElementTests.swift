import Foundation
import Testing

import ReadiumShared
import StoryArcCore
@testable import EpubReaderFeature

/// `reading-progress`, *Resume at the first visible element*, decision O27. Android's
/// `FirstVisibleElementTest` makes the same assertions.
@Suite("A resume goes to the first visible element")
struct FirstVisibleElementTests {

    private let element = ElementLocator(
        href: "OEBPS/ch1.xhtml",
        cssSelector: "body > p:nth-child(18)",
        textBefore: "the end of seventeen. ",
        textAfter: "Paragraph eighteen begins",
        publicationDigest: "d2"
    )

    /// The place a fraction names: page 3 of chapter one, one page after the element's page.
    private func fraction(in href: String) -> Locator {
        Locator(
            href: AnyURL(string: href) ?? AnyURL(url: URL(fileURLWithPath: href)),
            mediaType: .xhtml,
            locations: .init(progression: 0.52, totalProgression: 0.26)
        )
    }

    private func position(_ element: ElementLocator?) -> ReadingPosition {
        .reflowable(progression: 0.26, locator: "", firstVisibleElement: element)
    }

    @Test("A stored element wins over a fraction that points one page away")
    func theElementWins() throws {
        let resumed = try #require(
            FirstVisibleElement.resume(fraction(in: "OEBPS/ch1.xhtml"), from: position(element), digest: "d2")
        )

        #expect(resumed.locations.cssSelector == "body > p:nth-child(18)")
        #expect(resumed.text.highlight == "Paragraph eighteen begins")
        #expect(resumed.text.before == "the end of seventeen. ")
        #expect(resumed.href.string == "OEBPS/ch1.xhtml")
    }

    @Test("A different resource falls back to the fraction")
    func anotherResourceFallsBack() {
        let fallback = fraction(in: "OEBPS/ch2.xhtml")

        #expect(FirstVisibleElement.resume(fallback, from: position(element), digest: "d2") == fallback)
    }

    @Test("A different file, or no element, falls back to the fraction")
    func anotherFileFallsBack() {
        let fallback = fraction(in: "OEBPS/ch1.xhtml")

        #expect(FirstVisibleElement.resume(fallback, from: position(element), digest: "d9") == fallback)
        #expect(FirstVisibleElement.resume(fallback, from: position(nil), digest: "d2") == fallback)
    }
}
