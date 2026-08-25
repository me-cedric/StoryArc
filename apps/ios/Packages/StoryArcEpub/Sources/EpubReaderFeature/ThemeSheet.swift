public import SwiftUI

internal import DesignSystem
public import StoryArcCore

/// The reading-theme sheet.
///
/// `ebook-reader` and `reading-themes` between them ask for a preset grid, a
/// stepped font size with a visible position, and — the part that is easy to skip —
/// an axis that cannot reach the page shown "unavailable with a one-line reason and
/// a single action that turns publisher styles off". Not hidden, and not a live
/// control that does nothing.
///
/// The fine axes — line, character, word and paragraph spacing, margins, alignment,
/// custom background — are Phase 3.5 and 3.7 of the change and are not here yet.
/// What is here is the first level the spec describes.
struct ThemeSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    let model: EpubReaderModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: StoryArcSpace.xl) {
                    presets
                    fontSize
                    if model.theme.preset.keepsPublisherStyles { publisherNotice }
                }
                .padding(StoryArcSpace.gutter)
            }
            .background(theme.palette.surfaceCanvas)
            .navigationTitle(Text("theme.title", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("theme.done", bundle: .module) }
                }
                if model.theme.isModified {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { model.restoreTheme() } label: {
                            Text("theme.restore", bundle: .module)
                        }
                    }
                }
            }
        }
    }

    /// Three by two, each card in its own colours.
    ///
    /// `ebook-reader`: the grid previews "each preset in its own colours — six
    /// samples, not six labels". A swatch that took the app's palette would be six
    /// identical cards with different words on them.
    private var presets: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.sm) {
            Text("theme.presets", bundle: .module)
                .textRole(.headline)
                .foregroundStyle(theme.palette.textPrimary)

            LazyVGrid(
                columns: Array(repeating: GridItem(spacing: StoryArcSpace.sm), count: 3),
                spacing: StoryArcSpace.sm
            ) {
                ForEach(ThemePreset.allCases, id: \.self) { preset in
                    PresetCard(
                        preset: preset,
                        isActive: model.theme.preset == preset,
                        isModified: model.theme.preset == preset && model.theme.isModified
                    ) {
                        model.adopt(preset)
                    }
                }
            }
        }
    }

    /// `reading-themes`: stepped, with the position shown, never a free slider.
    private var fontSize: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.sm) {
            Text("theme.fontSize", bundle: .module)
                .textRole(.headline)
                .foregroundStyle(theme.palette.textPrimary)

            HStack(spacing: StoryArcSpace.md) {
                Button { step(to: model.values.fontSize.previous) } label: {
                    Label {
                        Text("theme.fontSize.smaller", bundle: .module)
                    } icon: {
                        Image(systemName: "textformat.size.smaller")
                    }
                    .labelStyle(.iconOnly)
                }
                .disabled(model.values.fontSize == FontSizeStep.allCases.first)

                StepDots(position: model.values.fontSize.position, count: FontSizeStep.count)

                Button { step(to: model.values.fontSize.next) } label: {
                    Label {
                        Text("theme.fontSize.larger", bundle: .module)
                    } icon: {
                        Image(systemName: "textformat.size.larger")
                    }
                    .labelStyle(.iconOnly)
                }
                .disabled(model.values.fontSize == FontSizeStep.allCases.last)
            }
            .buttonStyle(.bordered)

            Text("theme.fontSize.percent \(model.values.fontSize.rawValue)", bundle: .module)
                .textRole(.footnote)
                .monospacedDigit()
                .foregroundStyle(theme.palette.textTertiary)
        }
        // One control, spoken as one: `reading-themes` asks for increment actions so
        // VoiceOver can adjust it rather than hunting two buttons.
        .accessibilityElement(children: .combine)
        .accessibilityValue(
            Text("theme.fontSize.percent \(model.values.fontSize.rawValue)", bundle: .module)
        )
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: step(to: model.values.fontSize.next)
            case .decrement: step(to: model.values.fontSize.previous)
            @unknown default: break
            }
        }
    }

    private func step(to size: FontSizeStep) {
        var values = model.values
        values.fontSize = size
        model.change(.fontSize, to: values)
    }

    /// What Original costs, said once rather than implied by dead sliders.
    private var publisherNotice: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.sm) {
            Text("theme.publisherStyles.title", bundle: .module)
                .textRole(.headline)
                .foregroundStyle(theme.palette.textPrimary)

            Text("theme.publisherStyles.reason", bundle: .module)
                .textRole(.footnote)
                .foregroundStyle(theme.palette.textSecondary)

            // The single action the spec asks for. It names what it does rather than
            // saying "fix": turning publisher styles off is a real choice about
            // whose typography wins.
            Button { model.leavePublisherStyles() } label: {
                Text("theme.publisherStyles.action", bundle: .module)
            }
            .buttonStyle(.bordered)

            VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                ForEach(ThemeAxis.allCases.filter(\.requiresPublisherStylesOff), id: \.self) { axis in
                    Text(axis.titleKey, bundle: .module)
                        .textRole(.caption)
                        .foregroundStyle(theme.palette.textTertiary)
                }
            }
        }
        .padding(StoryArcSpace.md)
        .background(theme.palette.surfaceRaised, in: .rect(cornerRadius: StoryArcRadius.lg))
    }
}

/// One preset, previewed in its own colours.
private struct PresetCard: View {
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
private struct StepDots: View {
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

private extension Color {
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
