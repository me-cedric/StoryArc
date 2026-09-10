internal import CoreGraphics

internal import DesignSystem

/// How wide one *Keep reading* card is in the room the shelf was given.
///
/// Its own type because ``HomeHero`` is at the file's line ceiling, and because a number
/// computed inside a `View` cannot be asserted. `HomeHeroWidthTests` is what asserts it.
enum HomeHeroMetrics {

    /// How many cards fit across, counting the one that only peeks.
    ///
    /// `home-screen`: "about one and a half cards fit across a phone, so the second is
    /// plainly a second and not a thumbnail beside a hero". A share of the width rather
    /// than a fixed size, because the peek is what says the row scrolls.
    static let cardsAcross: CGFloat = 1.5

    /// The widest a card grows. A phone never reaches either number.
    ///
    /// Two of them by window width, which is §3.11's "fewer, larger, more confident covers,
    /// not the same phone lattice widened". One cap sized for a phone left a 13-inch iPad
    /// showing a hero the size of a paperback with half the window empty beside it; the
    /// wide cap is still well short of a frame the size of a page, which is what the single
    /// number was protecting against in the first place.
    static let widestCard: CGFloat = 420
    static let widestCardInAWideWindow: CGFloat = 560

    /// Cover proportions, opened out a little. Comic trim is 2:3; the card is 4:5, which
    /// is enough room for the caption without either cropping the art or leaving a band of
    /// wash under every cover.
    static let cardAspect: CGFloat = 1.25

    /// The cap this window earns.
    ///
    /// Measured rather than read from `horizontalSizeClass`, for the reason ``CoverGrid``
    /// gives: the same iPad hands this shelf a good 300 pt less once the sidebar is out,
    /// and less again in a Split View slot. The input is the width the shelf actually got.
    static func widest(inRoomOf available: CGFloat) -> CGFloat {
        available >= StoryArcWindowClass.sidebarWidthThreshold ? widestCardInAWideWindow : widestCard
    }

    /// One card in a row of them.
    ///
    /// The gutters come off first, so the arithmetic is over the room the cards actually
    /// have rather than over the window. Dividing the window itself is what put two and a
    /// half cards on a phone that was asked for one and a half.
    static func cardWidth(inRoomOf available: CGFloat) -> CGFloat {
        let room = max(available - StoryArcSpace.gutter * 2, 0)
        return min(room / cardsAcross, widest(inRoomOf: available))
    }

    /// The lone card takes the width between the gutters, because there is nothing beside
    /// it for a peek to promise.
    static func soloWidth(inRoomOf available: CGFloat) -> CGFloat {
        min(max(available - StoryArcSpace.gutter * 2, 0), widest(inRoomOf: available))
    }
}
