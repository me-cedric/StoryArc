import CoreGraphics
import StoryArcCore

/// Whether a reader window shows two pages, and which page lands on which side.
///
/// `desktop-experience`, *Two-page spreads by window shape*: pairs when the window is wide
/// enough, one page when it is not, the cover alone on the first screen, a wide page alone
/// and full width, the last page of an odd count alone and centred. The pairing itself is
/// `SpreadLayout.paired` from `StoryArcCore`, the arithmetic iOS and Android share; this
/// adds the window-shape rule and the screen order. Task 2.14.
enum SpreadDecision {
    /// Two portrait pages side by side are about 4:3. A window at or past this aspect
    /// pairs; a narrower one shows one page.
    static let pairingAspect: CGFloat = 1.25

    static func pairs(viewport: CGSize) -> Bool {
        viewport.height > 0 && viewport.width / viewport.height >= pairingAspect
    }

    /// The layout for a window of this shape.
    ///
    /// - Parameter coverAlone: the spec's default on a desktop. A reader may pair the cover
    ///   with page two by turning it off, which is the iOS pairing offset the other way up.
    static func layout(pageCount: Int, wide: Set<Int>, pairs: Bool, coverAlone: Bool = true) -> SpreadLayout {
        guard pairs else { return .single(pageCount: pageCount) }
        return .paired(pageCount: pageCount, wide: wide, isOffset: coverAlone)
    }

    /// The pages of a slot from the left of the screen to the right.
    ///
    /// Right-to-left puts the page read first on the right, so a manga spread reads 4 then
    /// 5 with 4 on the right, as `comic-reader` asks. A lone page is centred by the view
    /// and no blank is drawn beside it.
    static func screenOrder(_ spread: Spread, isRightToLeft: Bool) -> [Int] {
        isRightToLeft ? spread.pages.reversed() : spread.pages
    }
}
