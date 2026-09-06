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
        #expect(coverMinimumWidth(shelfWidth: 839, textSize: size) == 132)
        #expect(coverMinimumWidth(shelfWidth: 840, textSize: size) == 158)
        #expect(coverMinimumWidth(shelfWidth: 1366, textSize: size) == 158)
    }

    /// One wide-tier threshold, and 760 does not reach it.
    ///
    /// Decided on 2026-09-06 and recorded in `design.md` §4. `confidentShelfWidth` was 900
    /// and Android's threshold has always been 840, which is Material's expanded breakpoint.
    /// Both platforms hand the tier a measured shelf width, so it is the app's own number
    /// rather than a platform size class, and two of them were a divergence neither platform
    /// forces. Android asserts this boundary under this same name, so they cannot drift apart
    /// again.
    ///
    /// **The pane reading of 840 is Android's.** There it is also
    /// `StoryArcWindowClass.showsTwoPanes` — a member iOS's type of that name does not have.
    /// The only iOS second pane is ``LibraryPanes``'s split view, on the shelf surface alone,
    /// turned on by the horizontal size class near 600 pt.
    ///
    /// **760 is not a device.** It is the ceiling ``LibraryPanes`` puts on the library
    /// column, so it is the widest the *library* shelf is ever drawn, and it still takes the
    /// middle tier. The library grid reaches the wide tier under no number this file names.
    @Test(
        "The wide tier starts at 840, the one number both platforms use",
        arguments: ordinarySizes
    )
    func theWideTierStartsAtTheOneSharedNumber(size: DynamicTypeSize) {
        #expect(coverMinimumWidth(shelfWidth: 839, textSize: size) == 132)
        #expect(coverMinimumWidth(shelfWidth: 840, textSize: size) == 158)
        #expect(coverMinimumWidth(shelfWidth: 760, textSize: size) == 132)
    }

    /// The band the decision moved, asserted at its middle.
    ///
    /// No iPad has a full-screen *window* in [840, 899), which bounds the window and not
    /// this function's input — a shelf is a column, and `confidentShelfWidth` says why the
    /// affected set is a lower bound. What is certain is the resized window: the app sets no
    /// `UIRequiresFullScreen` and `native-experience` asks one to reflow continuously, so a
    /// window dragged to 870 pt is a full-width shelf inside the band. It drew the 132 pt
    /// tier before this decision and draws 158 after it. Android drew 158 there already, so
    /// this test is a pin there and a changed answer here.
    @Test(
        "A shelf of 870 takes the wide tier, the band iOS moved on 2026-09-06",
        arguments: ordinarySizes
    )
    func theBandTheDecisionMovedTakesTheWideTier(size: DynamicTypeSize) {
        #expect(coverMinimumWidth(shelfWidth: 870, textSize: size) == 158)
    }

    /// Every shelf width an iPad can hand this function from a full window, plus the one
    /// cap the library shelf carries.
    ///
    /// The device widths are the current iPad line's own, read on 2026-09-06 from the
    /// simulator device profiles — `mainScreenWidth / mainScreenScale`, in points, portrait
    /// then landscape. 744 and 1133 are the mini, 820 and 1180 the iPad and the 11-inch
    /// Air, 834 and 1210 the 11-inch Pro, 1024 and 1366 the 13-inch Air, 1032 and 1376 the
    /// 13-inch Pro. No iPad has a full-window width in [840, 899), which is why every width
    /// here answers the same whether the wide tier starts at 840 or at 900. The widths that
    /// do not are 839, 840 and 870, and they are asserted above.
    @Test(
        "Each shelf width an iPad can offer takes the tier it takes",
        arguments: ordinarySizes
    )
    func everySupportedWidthTakesItsTier(size: DynamicTypeSize) {
        for width in [CGFloat(744), 760, 820, 834] {
            #expect(
                coverMinimumWidth(shelfWidth: width, textSize: size) == 132,
                "a shelf of \(width) pt left the middle tier"
            )
        }
        for width in [CGFloat(1024), 1032, 1133, 1180, 1210, 1366, 1376] {
            #expect(
                coverMinimumWidth(shelfWidth: width, textSize: size) == 158,
                "a shelf of \(width) pt left the wide tier"
            )
        }
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
