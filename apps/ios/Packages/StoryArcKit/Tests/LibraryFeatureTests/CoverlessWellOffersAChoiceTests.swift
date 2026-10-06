import CoreGraphics
import Testing

@testable import LibraryFeature
import StoryArcCore

/// Task 2.3: "the coverless well offers it".
///
/// The well "draws a glyph and a format name and offers nothing", which is what made a
/// publication with no artwork a dead end — the reason this whole change exists. It is the
/// entry point now, and a page that offers no choice still draws exactly the hero it drew
/// before, which is the second half of the same promise.
///
/// A rule rather than a composition, because this package's host suite composes nothing.
/// Android's `CoverlessWellOffersAChoiceTest` presses the well under Robolectric, which is the
/// stronger reach; `DetailHero/offersChoice` is the decision both of them turn on.
@Suite("The coverless well offers a choice")
struct CoverlessWellOffersAChoiceTests {

    private let publication = Publication(
        identity: PublicationIdentity(contentDigest: "bare"),
        format: .m4b,
        displayTitle: "Ripped From A CD",
        origin: .inferred
    )

    @Test("An empty well is the way to choose a cover")
    @MainActor
    func emptyWellActs() throws {
        // Pressed, not only asked about: `offersChoice` was a property beside the wiring, so a
        // hero that stopped handing the action to its well stayed green. This presses the
        // well the hero draws.
        var chose = false
        let hero = DetailHero(publication: publication, cover: nil, onChooseCover: { chose = true })
        #expect(hero.offersChoice)

        let press = try #require(hero.well.action)
        press()

        #expect(chose)
    }

    @Test("A page that offers no choice draws the hero it always drew")
    func noChoiceLeavesTheWellDecorative() {
        let hero = DetailHero(publication: publication, cover: nil)
        #expect(!hero.offersChoice)
        #expect(hero.well.action == nil)
    }

    @Test("A publication that has artwork is looked at rather than tapped")
    func artworkIsNotAButton() throws {
        // Tapping a cover is how a reader looks at it, so the hero only acts where there is
        // nothing to look at. The chooser is a control under the hero in that case — see
        // ``DetailCoverChoice``.
        let context = try #require(CGContext(
            data: nil,
            width: 2,
            height: 3,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let cover = try #require(context.makeImage())

        let hero = DetailHero(publication: publication, cover: cover, onChooseCover: {})

        #expect(!hero.offersChoice)
    }
}
