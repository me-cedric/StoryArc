import SwiftUI
import Testing

@testable import LibraryFeature

/// A cover's lower bound follows the room the shelf has **and** the reader's text size.
///
/// The width half is `design.md` §4 and was already here. The text-size half was not, and
/// the shelf showed what that costs: at the largest Dynamic Type size a 402 pt iPhone still
/// laid out three columns, so a cover captioned `Ashfall #1` hyphenated into `Ash-` /
/// `fall #1` and its neighbours' series lines truncated to `Ashf…`. The artwork stayed
/// recognisable and the caption stopped being readable, which is the wrong way round.
///
/// The column count itself is asserted on Android, in `BoundedAdaptiveTest`, where the
/// arithmetic is ours. SwiftUI owns it here, and a test of `GridItem(.adaptive(...))` would
/// be a test of SwiftUI. What the two platforms share is the pair of bounds.
@Suite("Cover minimum width")
struct CoverMinimumWidthTests {

    /// Every size the reader can choose that is *not* an accessibility size. The tiers
    /// `design.md` states must survive all of them unchanged.
    private static let ordinarySizes: [DynamicTypeSize] = [
        .xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge,
    ]

    private static let accessibilitySizes: [DynamicTypeSize] = [
        .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5,
    ]

    @Test(
        "The documented tiers hold at every ordinary text size",
        arguments: ordinarySizes
    )
    func documentedTiersAreUntouched(size: DynamicTypeSize) {
        // `design.md` §4: "Minimum cover width scales by size class: 104 / 132 / 158 pt."
        #expect(coverMinimumWidth(shelfWidth: 0, textSize: size) == 104)
        #expect(coverMinimumWidth(shelfWidth: 402, textSize: size) == 104)
        #expect(coverMinimumWidth(shelfWidth: 599, textSize: size) == 104)
        #expect(coverMinimumWidth(shelfWidth: 600, textSize: size) == 132)
        #expect(coverMinimumWidth(shelfWidth: 899, textSize: size) == 132)
        #expect(coverMinimumWidth(shelfWidth: 900, textSize: size) == 158)
        #expect(coverMinimumWidth(shelfWidth: 1366, textSize: size) == 158)
    }

    @Test(
        "Every tier steps once at an accessibility text size",
        arguments: accessibilitySizes
    )
    func everyTierStepsOnce(size: DynamicTypeSize) {
        // One step, not a scale that follows the font: AX1 and AX5 get the same cover,
        // because what a cramped caption needs is one fewer column and a column is a step.
        // Android's `coverMinimumWidth` lands on the same three numbers.
        #expect(coverMinimumWidth(shelfWidth: 402, textSize: size) == 146)
        #expect(coverMinimumWidth(shelfWidth: 700, textSize: size) == 185)
        #expect(coverMinimumWidth(shelfWidth: 1366, textSize: size) == 221)
    }

    /// The step exists to buy the caption a column, and the narrowest supported iPhone is
    /// where that is easiest to overshoot. A 375 pt SE has 335 pt of shelf between its
    /// gutters; SwiftUI fits `floor((335 + 12) / (minimum + 12))` columns in it — already
    /// two, so the SE has nothing to give and must not be pushed to one.
    @Test("The step takes every phone to two columns, and none of them to one")
    func aPhoneKeepsTwoColumns() {
        // `layout.json`: `gutter` 20 each side, `md` 12 between columns. Spelled out
        // rather than imported — `DesignSystem` is not a dependency of this test target,
        // and a shelf laid out with different numbers is a different claim anyway.
        let gutters: CGFloat = 20 * 2
        let spacing: CGFloat = 12

        func columns(shelfWidth: CGFloat, textSize: DynamicTypeSize) -> Int {
            let available = shelfWidth - gutters
            let minimum = coverMinimumWidth(shelfWidth: shelfWidth, textSize: textSize)
            return max(1, Int((available + spacing) / (minimum + spacing)))
        }

        // The two that carry the defect: three columns of hyphenated caption become two.
        #expect(columns(shelfWidth: 402, textSize: .large) == 3)
        #expect(columns(shelfWidth: 440, textSize: .large) == 3)

        // And the SE, which was already at two and is the one the step could overshoot.
        #expect(columns(shelfWidth: 375, textSize: .large) == 2)

        // Every iPhone width on the iOS 26 floor lands on two, and none on one.
        for width in [CGFloat(375), 402, 440] {
            #expect(columns(shelfWidth: width, textSize: .accessibility1) == 2)
            #expect(columns(shelfWidth: width, textSize: .accessibility5) == 2)
        }
    }

    /// The pair has to stay a range: a minimum above the maximum would invert the grid.
    /// `CoverGrid` derives the maximum as `minimum * 1.6`, so the step carries both.
    @Test("Every minimum stays under its maximum")
    func theRangeStaysARange() {
        for width in [CGFloat(0), 375, 402, 600, 900, 1366, 4000] {
            for size in Self.ordinarySizes + Self.accessibilitySizes {
                let minimum = coverMinimumWidth(shelfWidth: width, textSize: size)
                #expect(minimum < (minimum * 1.6).rounded())
            }
        }
    }
}
