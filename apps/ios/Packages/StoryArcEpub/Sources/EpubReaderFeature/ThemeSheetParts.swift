internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

// The sheet's smaller pieces: a preset card previewing its own colours, the
// step-position dots, the hex reader the swatches share with Readium, and the
// names the domain enums go by on screen. Split out of `ThemeSheet` so the sheet
// itself reads as its sections and nothing else.

/// One preset, previewed in its own colours.
struct PresetCard: View {
    @Environment(\.theme) private var theme

    let preset: ThemePreset
    let isActive: Bool
    let isModified: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: StoryArcSpace.xs) {
                ZStack {
                    Color(hex: ReadingTheme(preset: preset).background)
                    // Two lines of nothing in the preset's own text colour: a sample
                    // of the pairing, which is what the reader is choosing.
                    VStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { _ in
                            Capsule()
                                .fill(Color(hex: ReadingTheme(preset: preset).foreground))
                                .frame(height: 2)
                        }
                    }
                    .padding(.horizontal, StoryArcSpace.sm)
                }
                .frame(height: 44)
                .clipShape(.rect(cornerRadius: StoryArcRadius.sm))
                .overlay {
                    RoundedRectangle(cornerRadius: StoryArcRadius.sm)
                        .strokeBorder(
                            isActive ? theme.accent : theme.palette.borderSubtle,
                            lineWidth: isActive ? 2 : 1
                        )
                }

                Text(preset.titleKey, bundle: .module)
                    .textRole(.caption)
                    // Weight as well as colour: colour is never the only signal.
                    .fontWeight(isActive ? .semibold : .regular)
                    .foregroundStyle(isActive ? theme.accent : theme.palette.textSecondary)
                    .lineLimit(1)

                if isModified {
                    Text("theme.modified", bundle: .module)
                        .textRole(.caption)
                        .foregroundStyle(theme.palette.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }
}

/// Where the size sits on its ladder.
struct StepDots: View {
    @Environment(\.theme) private var theme

    let position: Int
    let count: Int

    var body: some View {
        HStack(spacing: StoryArcSpace.hair) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == position ? theme.accent : theme.palette.borderSubtle)
                    .frame(width: index == position ? 7 : 5, height: index == position ? 7 : 5)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

extension Color {
    /// The tokens emit hex for Readium; the swatch reads the same string, so the
    /// card and the page cannot show different colours.
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.hasPrefix("#") ? String(hex.dropFirst()) : hex)
            .scanHexInt64(&value)
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension ThemePreset {
    var titleKey: LocalizedStringKey {
        switch self {
        case .original: "theme.preset.original"
        case .quiet: "theme.preset.quiet"
        case .paper: "theme.preset.paper"
        case .bold: "theme.preset.bold"
        case .calm: "theme.preset.calm"
        case .focus: "theme.preset.focus"
        }
    }
}

extension ThemeAxis {
    var titleKey: LocalizedStringKey {
        switch self {
        case .fontSize: "theme.axis.fontSize"
        case .fontFamily: "theme.axis.fontFamily"
        case .boldText: "theme.axis.boldText"
        case .lineSpacing: "theme.axis.lineSpacing"
        case .characterSpacing: "theme.axis.characterSpacing"
        case .wordSpacing: "theme.axis.wordSpacing"
        case .paragraphSpacing: "theme.axis.paragraphSpacing"
        case .margins: "theme.axis.margins"
        case .textAlignment: "theme.axis.textAlignment"
        }
    }
}

extension ReaderTypeface {
    var titleKey: LocalizedStringKey {
        switch self {
        case .publisher: "theme.typeface.publisher"
        case .serif: "theme.typeface.serif"
        case .sans: "theme.typeface.sans"
        }
    }
}

extension ReaderTextAlignment {
    var titleKey: LocalizedStringKey {
        switch self {
        case .publisher: "theme.alignment.publisher"
        case .left: "theme.alignment.left"
        case .justified: "theme.alignment.justified"
        }
    }
}
