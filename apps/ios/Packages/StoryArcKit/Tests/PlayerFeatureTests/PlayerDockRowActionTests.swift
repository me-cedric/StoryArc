import Foundation
import Testing

@testable import PlayerFeature
@testable import Playback
import StoryArcCore

/// D17: the inline compact bar gives a read-aloud publication one tap to the full player.
///
/// `read-aloud-and-reader-theming`: "the transport outside the reader" must reach sentence
/// skip without going back through the book first. Before this decision, the inline row for a
/// publication being read aloud opened the book (``PlayerWayBack/publication``) because the
/// chevron that otherwise carries the trip to the full player is hidden inline — see
/// ``PlayerDock/controls(_:)``. D17 settles it: the row itself opens the player when there is
/// no room for a second control.
///
/// **Proved able to fail**, per AGENTS.md §5: changing the `.publication` branch to
/// `return .returnToPublication` unconditionally (deleting the `isInline` check) failed *The
/// inline row opens the player for a publication being read aloud* by name. Reverted.
@Suite("Where the compact bar's row goes")
struct PlayerDockRowActionTests {

    @Test("A narrated audiobook always opens the player — there is no book to go back to")
    func narratedAudiobook() {
        #expect(playerDockRowAction(wayBack: .fullPlayer, isInline: false) == .openPlayer)
        #expect(playerDockRowAction(wayBack: .fullPlayer, isInline: true) == .openPlayer)
    }

    @Test("The inline row opens the player for a publication being read aloud")
    func inlinePublicationOpensPlayer() {
        #expect(playerDockRowAction(wayBack: .publication, isInline: true) == .openPlayer)
    }

    @Test("Outside the inline placement, the row still goes straight back to the book")
    func fullSizeRowReturnsToPublication() {
        #expect(playerDockRowAction(wayBack: .publication, isInline: false) == .returnToPublication)
    }

    // MARK: - The full player's way back (D17)

    private func bar(_ format: PublicationFormat) throws -> CompactPlayer {
        let book = SpokenBook(
            publication: Publication(
                identity: PublicationIdentity(normalizedPath: "/library/the-long-field.\(format)"),
                format: format,
                displayTitle: "The Long Field",
                origin: .inferred
            ),
            url: URL(fileURLWithPath: "/library/the-long-field.\(format)")
        )
        return try #require(CompactPlayer.of(PlaybackSession().started(), playing: book))
    }

    @Test("The full player carries the way back to a book being read aloud")
    func fullPlayerCarriesTheWayBack() throws {
        let reading = try bar(.epub)
        #expect(fullPlayerWayBack(reading) == reading.book)
    }

    @Test("A narrated audiobook's full player has no book to go back to")
    func narratedAudiobookHasNoWayBack() throws {
        #expect(fullPlayerWayBack(try bar(.m4b)) == nil)
        #expect(fullPlayerWayBack(nil) == nil)
    }
}
