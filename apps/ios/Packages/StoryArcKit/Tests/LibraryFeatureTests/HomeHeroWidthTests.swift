import CoreGraphics
import Testing

import DesignSystem
@testable import LibraryFeature

/// How wide one *Keep reading* card is.
///
/// `home-screen`, *The hero does not crowd out the rest of the surface*: "about one and a
/// half cards fit across a phone, so the second is plainly a second and not a thumbnail
/// beside a hero". The Android twin is `HomeCoverWidthTest`, and the two rows are meant to
/// be the same row drawn twice.
///
/// The share used to be 0.86 of the window, which put one card and a sliver on a phone.
@Suite("One and a half cards fit across a phone")
struct HomeHeroWidthTests {

    private let phone: CGFloat = 393
    private let room: (CGFloat) -> CGFloat = { $0 - StoryArcSpace.gutter * 2 }

    @Test("A phone gets one and a half cards, measured over the room and not the window")
    func aPhoneGetsOneAndAHalf() {
        let width = HomeHeroMetrics.cardWidth(inRoomOf: phone)

        #expect(width == room(phone) / 1.5)
        #expect(abs(room(phone) / width - 1.5) < 0.001)
    }

    @Test("A card never outgrows the room it was given, at any width")
    func aCardStaysInsideTheRoom() {
        for available in [320, 375, 393, 430, 600, 834, 1024, 1366].map(CGFloat.init) {
            let width = HomeHeroMetrics.cardWidth(inRoomOf: available)
            #expect(width <= room(available), "a \(available) pt shelf gave a \(width) pt card")
            #expect(width > 0)
        }
    }

    @Test("A wide window caps the card rather than letting it grow with the sidebar out")
    func aWideWindowCaps() {
        #expect(HomeHeroMetrics.cardWidth(inRoomOf: 1366) == HomeHeroMetrics.widestCardInAWideWindow)
        #expect(HomeHeroMetrics.cardWidth(inRoomOf: 599) <= HomeHeroMetrics.widestCard)
    }

    @Test("The lone card takes the whole room, because nothing peeks beside it")
    func theLoneCardTakesTheRoom() {
        #expect(HomeHeroMetrics.soloWidth(inRoomOf: phone) == room(phone))
        #expect(HomeHeroMetrics.soloWidth(inRoomOf: phone) > HomeHeroMetrics.cardWidth(inRoomOf: phone))
    }

    @Test("A window narrower than its own gutters asks for nothing, not for a negative card")
    func aWindowWithNoRoom() {
        #expect(HomeHeroMetrics.cardWidth(inRoomOf: 8) == 0)
        #expect(HomeHeroMetrics.soloWidth(inRoomOf: 8) == 0)
    }
}
