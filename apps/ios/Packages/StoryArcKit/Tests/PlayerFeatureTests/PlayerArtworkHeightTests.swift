import CoreGraphics
import Testing

@testable import PlayerFeature

/// `audio-playback`: "no transport control is pushed off the screen", on the outer display of
/// an iPhone Duo too (`foldables-and-iphone-duo` 2.5). Android's `playerArtworkMax` is the same rule.
@Suite("The player's artwork gives up height to the transport")
struct PlayerArtworkHeightTests {
    @Test("The artwork takes what the transport leaves: the screen less the controls and two gaps")
    func takesWhatIsLeft() {
        // 582 points of a 678-point outer display inside its safe area, 220 of them under the
        // cover, and two gaps of 24: 314 for the artwork.
        #expect(PlayerArtwork.maxHeight(viewport: 582, underneath: 220) == 314)
    }

    @Test("Never below 120 points, so a short screen at the largest text size still has a picture")
    func neverBelowTheFloor() {
        #expect(PlayerArtwork.maxHeight(viewport: 400, underneath: 380) == 120)
    }

    @Test("No cap before the screen is measured")
    func unmeasured() {
        #expect(PlayerArtwork.maxHeight(viewport: 0, underneath: 220) == nil)
    }
}
