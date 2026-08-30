import Foundation
import Testing

import ReadiumShared
import StoryArcCore
@testable import EpubReaderFeature

/// The way back from a jump.
///
/// `ebook-reader`'s "Returning from any jump" is three rules in one scenario: the control
/// is offered after a long jump, it is offered *until it is used or another jump replaces
/// it*, and "using it does not itself become somewhere to return from". None of the three
/// is visible in the pixels — a control that never went away and a control that re-armed
/// itself look identical on the page they left the reader on — so they are asserted here.
///
/// No publication is opened. What is under test is which position is written down and when
/// it is cleared, and opening a real EPUB to reach that would test Readium rather than
/// this. Android's `ReturnPointTest` makes the same five assertions in the same order.
@MainActor
@Suite("EPUB return point")
struct ReturnPointTests {

    private func model() -> EpubReaderModel {
        EpubReaderModel(
            publication: Publication(
                identity: PublicationIdentity(normalizedPath: "/nowhere.epub"),
                format: .epub,
                displayTitle: "nowhere",
                origin: .embedded
            ),
            url: URL(fileURLWithPath: "/nowhere.epub")
        )
    }

    /// A position, the way the navigator reports one.
    ///
    /// The fallback is unreachable for the hrefs below and exists because `force_unwrapping`
    /// is banned: a relative path is a valid URL, and one that were not would still make a
    /// file URL rather than a crash in a test about something else.
    private func page(_ href: String) -> Locator {
        Locator(
            href: AnyURL(string: href) ?? AnyURL(url: URL(fileURLWithPath: href)),
            mediaType: .xhtml
        )
    }

    /// A model whose reader is on a page.
    private func reader(at href: String) -> EpubReaderModel {
        let reader = model()
        reader.locator = page(href)
        return reader
    }

    @Test("A jump remembers where the reader was")
    func aJumpRemembersWhereTheReaderWas() throws {
        let reader = reader(at: "OEBPS/ch1.xhtml")

        reader.markReturnPoint()

        let point = try #require(reader.returnPoint)
        #expect(point.contains("ch1.xhtml"))
    }

    @Test("With nowhere recorded, nothing is offered")
    func withNowhereRecordedNothingIsOffered() {
        let reader = model()

        reader.markReturnPoint()

        // A book that has not reported a position yet. The control is absent rather than
        // present and refusing, which is the same rule the read-aloud button follows.
        #expect(reader.returnPoint == nil)
    }

    @Test("A second jump replaces the first rather than stacking")
    func aSecondJumpReplacesTheFirstRatherThanStacking() throws {
        let reader = reader(at: "OEBPS/ch1.xhtml")
        reader.markReturnPoint()

        reader.locator = page("OEBPS/ch9.xhtml")
        reader.markReturnPoint()

        // One point, not a stack. The control answers "take me back", and a reader who
        // has followed four links in a row means where they were reading, not the third
        // link.
        let point = try #require(reader.returnPoint)
        #expect(point.contains("ch9.xhtml"))
    }

    @Test("The point is taken once, so the control goes away")
    func thePointIsTakenOnceSoTheControlGoesAway() async throws {
        let reader = reader(at: "OEBPS/ch1.xhtml")
        reader.markReturnPoint()

        await reader.returnToWhereTheyWere()

        #expect(reader.returnPoint == nil)
    }

    @Test("Returning does not itself become somewhere to return from")
    func returningDoesNotItselfBecomeSomewhereToReturnFrom() async throws {
        let reader = reader(at: "OEBPS/ch9.xhtml")
        reader.markReturnPoint()
        await reader.returnToWhereTheyWere()

        // The move the return itself makes. Nothing marks a point on the way back, so a
        // reader is never handed a button that bounces them between two pages for ever.
        reader.locator = page("OEBPS/ch1.xhtml")

        #expect(reader.returnPoint == nil)
    }
}
