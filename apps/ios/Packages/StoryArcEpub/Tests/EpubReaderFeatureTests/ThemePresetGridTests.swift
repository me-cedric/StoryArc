import SwiftUI
import Testing

@testable import EpubReaderFeature

/// How many preset cards share a row, and why it is not always three.
///
/// **Photographed before it was fixed**: at `AccessibilityXXXL` on a 402 pt phone the grid was
/// three fixed columns, leaving each card about 170 pt, and *Original* drew as `Origi-` over
/// `nal`. A preset card is the one control in this app whose label may not shrink to fit — the
/// grid exists so each name is drawn in its **own** typeface at its own weight, so shrinking
/// the name shows the reader the wrong typeface, which is the thing being chosen.
///
/// The frames are `ios-epub-theme-presets-ax5{,-dark}.png`. This suite is the half of that
/// which runs without a device.
@Suite("The theme preset grid reflows")
@MainActor
struct ThemePresetGridTests {

    /// Every accessibility size gets one card per row.
    ///
    /// One and not two: two columns leave roughly 170 pt against a name needing about 250 pt at
    /// these sizes, so two would move the wrap rather than prevent it.
    @Test(
        "One column at every accessibility size",
        arguments: [
            DynamicTypeSize.accessibility1,
            .accessibility2,
            .accessibility3,
            .accessibility4,
            .accessibility5,
        ]
    )
    func oneColumnWhenTextIsLarge(size: DynamicTypeSize) {
        #expect(ThemeSheet.presetColumns(for: size) == 1)
    }

    /// And the ordinary sizes keep the three-by-two grid the design asks for.
    ///
    /// Asserted across the whole range rather than at one size, because the defect was a
    /// constant: a rule that answered 1 everywhere would satisfy the case above and quietly
    /// throw away the layout for every reader who has not raised their text size.
    @Test(
        "Three columns at every ordinary size",
        arguments: [
            DynamicTypeSize.xSmall,
            .small,
            .medium,
            .large,
            .xLarge,
            .xxLarge,
            .xxxLarge,
        ]
    )
    func threeColumnsWhenTextIsOrdinary(size: DynamicTypeSize) {
        #expect(ThemeSheet.presetColumns(for: size) == 3)
    }
}
