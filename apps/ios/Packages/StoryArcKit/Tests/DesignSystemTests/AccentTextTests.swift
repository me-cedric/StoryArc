import Foundation
import SwiftUI
import Testing

@testable import DesignSystem
import StoryArcCore

/// `close-the-audited-gaps` 27.4, owner answer O30: the accent and the danger colour drawn as
/// text reach 4.5:1. `pnpm tokens:check` gates the token values. This asks each palette the app
/// can draw for the ratio of every text pair a label really uses, so a palette wired to the
/// accent fill instead of the text colour fails here.
@Suite("Accent and danger as text")
struct AccentTextTests {
    private static let floor = 4.5

    private static let palettes: [(String, Palette)] = [
        ("dark", .dark), ("light", .light), ("oledDark", .oledDark),
        ("naturalLight", .naturalLight), ("naturalDark", .naturalDark),
    ]

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

    private func surfaces(of palette: Palette) -> [(String, Color)] {
        [
            ("canvas", palette.surfaceCanvas), ("raised", palette.surfaceRaised),
            ("overlay", palette.surfaceOverlay), ("sunken", palette.surfaceSunken),
        ]
    }

    @Test("Every palette's accent text reaches 4.5:1 on each of its surfaces")
    func accentTextClearsTheFloor() {
        for (name, palette) in Self.palettes {
            for (surface, colour) in surfaces(of: palette) {
                let ratio = contrast(palette.accentText, colour)
                #expect(ratio >= Self.floor, "\(name): accent text on \(surface) is \(ratio):1")
            }
        }
    }

    @Test("Every palette's danger text reaches 4.5:1 on each of its surfaces")
    func dangerTextClearsTheFloor() {
        for (name, palette) in Self.palettes {
            for (surface, colour) in surfaces(of: palette) {
                let ratio = contrast(palette.dangerText, colour)
                #expect(ratio >= Self.floor, "\(name): danger text on \(surface) is \(ratio):1")
            }
        }
    }

    @Test("The accent fill is not the text colour on the brand ramps")
    func brandAccentIsNotText() {
        #expect(Palette.light.accentText != Palette.light.accent)
        #expect(Palette.dark.accentText != Palette.dark.accent)
    }

    @Test("Increase Contrast keeps both text colours")
    func strengthenedKeepsTheTextColours() {
        #expect(Palette.light.strengthened.accentText == Palette.light.accentText)
        #expect(Palette.light.strengthened.dangerText == Palette.light.dangerText)
    }

    @Test("Without a cover the theme's text accent is the palette's")
    func themeFallsBackToThePalette() {
        #expect(Theme(palette: .light).accentText == Palette.light.accentText)
    }

    @Test("A cover accent is its own text accent")
    func coverAccentWins() {
        let theme = Theme(palette: .dark, coverAccent: .yellow, coverOnAccent: .black)

        #expect(theme.accentText == .yellow)
    }

    /// The environment tint is the text accent, so a prominent button, which fills with the accent,
    /// must name its own tint. Without one it fills with the lighter text accent and the white label
    /// on it falls under 4.5:1 on a dark canvas. This reads source text, the same trade
    /// `AccentReachesTheControlsTests` makes, because a resolved fill cannot be read on the host.
    @Test("Every prominent button names its own tint")
    func prominentButtonsNameTheirTint() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources")
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var untinted: [String] = []
        for case let file as URL in files where file.pathExtension == "swift" {
            let lines = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in lines.enumerated()
            where line.contains(".buttonStyle(.borderedProminent)") || line.contains(".buttonStyle(.glassProminent)") {
                let next = lines[(index + 1)..<min(index + 5, lines.count)]
                if !next.contains(where: { $0.contains(".tint(") }) {
                    untinted.append("\(file.lastPathComponent):\(index + 1)")
                }
            }
        }
        #expect(untinted.isEmpty, "A prominent button with no .tint within four lines: \(untinted)")
    }
}
