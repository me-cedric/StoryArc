import SwiftUI
import Testing

@testable import DesignSystem
import StoryArcCore

/// `close-the-audited-gaps` 25.7, owner answer O26: the label drawn on the accent reaches
/// 4.5:1. `pnpm tokens:check` gates the token values. This asks each palette the app can
/// draw, and the theme a cover accent builds, for the ratio of the pair a button really uses.
@Suite("Label on the accent")
struct OnAccentTests {
    private static let floor = 4.5

    private func luminance(_ color: Color) -> Double {
        let linear = color.resolve(in: EnvironmentValues())
        return 0.2126 * Double(linear.linearRed)
            + 0.7152 * Double(linear.linearGreen)
            + 0.0722 * Double(linear.linearBlue)
    }

    private func contrast(_ one: Color, _ other: Color) -> Double {
        let first = luminance(one)
        let second = luminance(other)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    @Test("Every palette's label reaches 4.5:1 on its own accent")
    func everyPaletteClearsTheFloor() {
        let palettes: [(String, Palette)] = [
            ("dark", .dark), ("light", .light), ("oledDark", .oledDark),
            ("naturalLight", .naturalLight), ("naturalDark", .naturalDark),
        ]
        for (name, palette) in palettes {
            let ratio = contrast(palette.onAccent, palette.accent)
            #expect(ratio >= Self.floor, "\(name): label on the accent is \(ratio):1")
        }
    }

    @Test("Increase Contrast keeps the label")
    func strengthenedKeepsTheLabel() {
        #expect(Palette.dark.strengthened.onAccent == Palette.dark.onAccent)
    }

    @Test("Without a cover the theme's label is the palette's")
    func themeFallsBackToThePalette() {
        #expect(Theme(palette: .light).onAccent == Palette.light.onAccent)
    }

    @Test("A cover accent brings the label that was derived for it")
    func coverLabelWins() {
        let theme = Theme(palette: .dark, coverAccent: .yellow, coverOnAccent: .black)

        #expect(theme.onAccent == .black)
        #expect(theme.onAccent != Palette.dark.onAccent)
    }
}
