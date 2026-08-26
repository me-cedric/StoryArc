internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// A reading background of the reader's own, kept legible.
///
/// `reading-themes` asks for four things here and they are easy to build three of:
/// swatches, a picker, a text colour derived at 7:1, and a refusal below 4.5:1
/// **with the measured ratio stated**. The last one is why the ratio is on screen at
/// all times rather than only when something goes wrong — a number that appears only
/// to scold is a number the reader has no reason to trust.
///
/// It is a seventh slot, not a seventh preset: choosing it keeps the typography the
/// reader already has, and tapping one of the six leaves it behind.
struct PageColourSection: View {
    @Environment(\.theme) private var theme

    let palette: ReaderPalette?
    let onAdopt: (ReaderPalette) -> Bool
    let onDiscard: () -> Void

    /// The ratio of the pairing that was last turned down, so it can be stated.
    @State private var refused: Double?
    @State private var picked = Color.white
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.sm) {
            Text("theme.pageColour", bundle: .module)
                .textRole(.headline)
                .foregroundStyle(theme.palette.textPrimary)
                // `textRole` sets font and tracking only, so without this the sheet's
                // one long ScrollView offers VoiceOver no heading to jump to.
                .accessibilityAddTraits(.isHeader)

            backgrounds

            ColorPicker(selection: $picked, supportsOpacity: false) {
                Text("theme.pageColour.pick", bundle: .module)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textSecondary)
            }
            .onChange(of: picked) { _, colour in
                guard let hex = colour.hexString else { return }
                adopt(ReaderPalette.derived(name: chosenName, background: hex))
            }

            if let palette {
                inUse(palette)
            }

            if let refused {
                // The number, not just the word. `reading-themes`: refused "with the
                // measured ratio stated", because "that is not allowed" without a
                // number is an obstacle rather than an explanation.
                Text(
                    "theme.pageColour.refused \(Self.formatted(refused)) \(Self.formatted(ReadingContrast.aa))",
                    bundle: .module
                )
                .textRole(.footnote)
                // Not the status red: #E94646 on this sheet's near-white material
                // measures 3.87:1, which would put the one sentence that names the
                // contrast floor below it.
                .foregroundStyle(theme.palette.textPrimary)
            }
        }
    }

    // MARK: - Sections

    private var backgrounds: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 44), spacing: StoryArcSpace.sm)],
            spacing: StoryArcSpace.sm
        ) {
            ForEach(ReaderPalette.suggestedBackgrounds, id: \.self) { hex in
                Swatch(
                    hex: hex,
                    isActive: palette?.background.caseInsensitiveCompare(hex) == .orderedSame
                ) {
                    adopt(ReaderPalette.derived(name: chosenName, background: hex))
                }
                .accessibilityLabel(Text("theme.pageColour.swatch \(hex)", bundle: .module))
            }
        }
    }

    /// The pairing in force: what it looks like, what it measures, what to do next.
    private func inUse(_ palette: ReaderPalette) -> some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.sm) {
            sample(palette)

            Text(
                "theme.pageColour.ratio \(Self.formatted(palette.contrast))",
                bundle: .module
            )
            .textRole(.footnote)
            .monospacedDigit()
            .foregroundStyle(theme.palette.textSecondary)

            if !palette.meetsAAA {
                // Not a refusal — 4.5 is the floor and this pairing is above it. But
                // every built-in preset clears 7:1, so a reader should know when
                // their own choice does not.
                Text("theme.pageColour.belowAAA", bundle: .module)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textTertiary)
            }

            // `reading-themes`: "a seventh, user-named slot". The name is the
            // reader's, so it is a field rather than something generated for them.
            TextField(
                text: $name,
                prompt: Text("theme.pageColour.name", bundle: .module)
            ) {
                Text("theme.pageColour.name", bundle: .module)
            }
            .textFieldStyle(.roundedBorder)
            .onSubmit { adopt(palette.renamed(to: chosenName)) }

            Text("theme.pageColour.textColour", bundle: .module)
                .textRole(.footnote)
                .foregroundStyle(theme.palette.textSecondary)

            foregrounds(palette)

            Button(role: .destructive) {
                refused = nil
                onDiscard()
            } label: {
                Text("theme.pageColour.clear", bundle: .module)
            }
            .buttonStyle(.bordered)
        }
    }

    /// Three lines of real text in the pairing, so the reader judges it as text.
    private func sample(_ palette: ReaderPalette) -> some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
            ForEach(0..<3, id: \.self) { _ in
                Text("theme.pageColour.sample", bundle: .module)
                    .textRole(.footnote)
                    .foregroundStyle(Color(hex: palette.foreground))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(StoryArcSpace.sm)
        .background(Color(hex: palette.background), in: .rect(cornerRadius: StoryArcRadius.sm))
        .overlay {
            RoundedRectangle(cornerRadius: StoryArcRadius.sm)
                .strokeBorder(theme.palette.borderSubtle, lineWidth: 1)
        }
        // Read aloud as one thing, and as what it is rather than as three lines of
        // filler a screen reader would otherwise recite.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("theme.pageColour.sample.label", bundle: .module))
    }

    private func foregrounds(_ palette: ReaderPalette) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 44), spacing: StoryArcSpace.sm)],
            spacing: StoryArcSpace.sm
        ) {
            ForEach(ReaderPalette.suggestedForegrounds, id: \.self) { hex in
                Swatch(
                    hex: hex,
                    isActive: palette.foreground.caseInsensitiveCompare(hex) == .orderedSame
                ) {
                    adopt(palette.overriding(foreground: hex))
                }
                .accessibilityLabel(Text("theme.pageColour.swatch \(hex)", bundle: .module))
            }
        }
    }

    // MARK: - Applying

    /// Applies a pairing, or remembers the ratio that stopped it.
    private func adopt(_ candidate: ReaderPalette) {
        guard onAdopt(candidate) else {
            refused = candidate.contrast
            // The reason renders at the foot of the section and the tapped swatch does
            // not move, so without this a VoiceOver user hears nothing and the measured
            // ratio never reaches the reader who was refused.
            let ratio = Self.formatted(candidate.contrast)
            let aa = Self.formatted(ReadingContrast.aa)
            AccessibilityNotification.Announcement(
                String(localized: "theme.pageColour.refused \(ratio) \(aa)", bundle: .module)
            ).post()
            return
        }
        refused = nil
    }

    /// The reader's name for the slot, or a default until they give it one.
    private var chosenName: String {
        name.trimmingCharacters(in: .whitespaces).isEmpty ? palette?.name ?? "" : name
    }

    private static func formatted(_ ratio: Double) -> String {
        ratio.formatted(.number.precision(.fractionLength(1)))
    }
}

/// One colour, tappable, with the selection shown by a ring rather than a tick.
///
/// A tick would have to be one colour or the other and would vanish against half
/// the swatches; a ring in the app's accent never does.
private struct Swatch: View {
    @Environment(\.theme) private var theme

    let hex: String
    let isActive: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            Circle()
                .fill(Color(hex: hex))
                .frame(height: 32)
                .overlay {
                    Circle().strokeBorder(theme.palette.borderSubtle, lineWidth: 1)
                }
                .overlay {
                    if isActive {
                        Circle()
                            .strokeBorder(theme.accent, lineWidth: 3)
                            .padding(-4)
                    }
                }
                // The circle stays 32 pt; the target does not. `contentShape` is what
                // widens the tap area — a bare frame leaves it the circle's own path.
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }
}

extension ReaderPalette {
    /// The same slot under a different name.
    func renamed(to name: String) -> ReaderPalette {
        ReaderPalette(name: name, background: background, foreground: foreground)
    }
}

extension Color {
    /// `#rrggbb`, or nil if the colour has no sRGB form.
    ///
    /// The picker hands back a `Color`; the domain, Readium and the tokens all speak
    /// hex. This is the one place that converts, so nothing else has to care that a
    /// `Color` is not a number.
    var hexString: String? {
        guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = UIColor(self).cgColor
                  .converted(to: sRGB, intent: .defaultIntent, options: nil),
              let components = converted.components,
              components.count >= 3
        else { return nil }
        let channels = components.prefix(3).map { Int(($0 * 255).rounded()) }
        return "#" + channels.map { String(format: "%02X", $0) }.joined()
    }
}
