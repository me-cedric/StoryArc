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
                    // Real letterforms in the preset's own face and colour.
                    // `reading-themes` asks each card to preview "its own colours and
                    // typeface", and a stack of grey rules — which is what this was —
                    // can show a colour but never a face.
                    Specimen(
                        typeface: preset.values.typeface,
                        colour: Color(hex: ReadingTheme(preset: preset).foreground),
                        isBold: preset.values.isBold
                    )
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

                // The name wraps rather than truncates. A card is a third of the sheet
                // wide, and at the largest text size a one-line caption clipped
                // "Original" to "Or…" — leaving the preset with no visible name at
                // all, since the specimen above it is hidden from assistive tech and
                // shows no words either. A grid row sizes to its tallest cell, so the
                // cards stay aligned.
                Text(preset.titleKey, bundle: .module)
                    .textRole(.caption)
                    // Weight as well as colour: colour is never the only signal.
                    .fontWeight(isActive ? .semibold : .regular)
                    .foregroundStyle(isActive ? theme.accent : theme.palette.textSecondary)

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

/// The reader's own palette, as a seventh card in the same grid.
///
/// Drawn from the same parts as a preset card, in its own colours, for the same
/// reason: a grid of samples reads at a glance and a grid of labels does not. It
/// carries the reader's name for the slot rather than the word "custom", because a
/// slot they named and cannot see the name of is not really theirs.
struct CustomCard: View {
    @Environment(\.theme) private var theme

    let palette: ReaderPalette
    /// The face in force, since a colour slot has none of its own.
    let typeface: ReaderTypeface
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: StoryArcSpace.xs) {
                ZStack {
                    Color(hex: palette.background)
                    Specimen(typeface: typeface, colour: Color(hex: palette.foreground))
                        .padding(.horizontal, StoryArcSpace.sm)
                }
                .frame(height: 44)
                .clipShape(.rect(cornerRadius: StoryArcRadius.sm))
                .overlay {
                    RoundedRectangle(cornerRadius: StoryArcRadius.sm)
                        .strokeBorder(theme.accent, lineWidth: 2)
                }

                title
                    .textRole(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.accent)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits([.isButton, .isSelected])
    }

    private var title: Text {
        let name = palette.name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? Text("theme.pageColour.untitled", bundle: .module) : Text(name)
    }
}

/// A few words in one face, for a card the size of a postage stamp.
///
/// Words rather than lorem ipsum: a reader judges a typeface by shapes they know.
/// Two short lines fit a 44-point card and still show ascenders, descenders and a
/// figure, which is most of what distinguishes one serif from another.
struct Specimen: View {
    let typeface: ReaderTypeface
    let colour: Color
    var isBold = false

    /// Fixed on purpose. See the note on the font below.
    private static let specimenSize: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("theme.specimen", bundle: .module)
            Text("theme.specimen.second", bundle: .module)
        }
        // A fixed size, so Dynamic Type does not scale it. A specimen is a *picture* of
        // a typeface and the card it sits in is a fixed height: at the largest text size
        // the words grow and the card clips them, which is a specimen that shows less of
        // the face the larger the reader needs it.
        .font(
            BundledFonts.font(
                typeface, size: Self.specimenSize, weight: isBold ? .bold : .regular
            )
        )
        .foregroundStyle(colour)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity, alignment: .leading)
        // One picture, and not a sentence a screen reader should read twice per card.
        .accessibilityHidden(true)
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

    /// The same name as a lookup *value*, for a sentence that takes it as an argument.
    ///
    /// `reading-themes` requires the reset to name the preset it restores — "the reader who
    /// modified Calm is offered Calm back" — and that name has to be resolved to a `String`
    /// before it can be interpolated into another localised sentence. A `LocalizedStringKey`
    /// cannot be: it is a key for `Text`, not a value.
    var localizedName: String.LocalizationValue {
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
        case .hyphenation: "theme.axis.hyphenation"
        }
    }
}

extension ReaderTypeface {
    var titleKey: LocalizedStringKey {
        switch self {
        case .publisher: "theme.typeface.publisher"
        case .serif: "theme.typeface.serif"
        case .sans: "theme.typeface.sans"
        // The bundled families go by their own names, which is how a reader
        // recognises them.
        case .literata: "theme.typeface.literata"
        case .sourceSerif: "theme.typeface.sourceSerif"
        case .ebGaramond: "theme.typeface.ebGaramond"
        case .bitter: "theme.typeface.bitter"
        case .atkinsonHyperlegible: "theme.typeface.atkinson"
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

extension PageTransition {
    /// How the page-turn modes are named in the theme sheet.
    ///
    /// A second copy of the comic reader's list, because the two features are separate
    /// packages with separate string catalogues — the alternative is a shared
    /// localisation target for five words.
    var titleKey: LocalizedStringKey {
        switch self {
        case .pageCurl: "theme.pageTurn.curl"
        case .slide: "theme.pageTurn.paginated"
        case .fastFade: "theme.pageTurn.fade"
        case .verticalScroll, .horizontalScroll: "theme.pageTurn.scroll"
        }
    }
}

extension TransitionUnavailability {
    var titleKey: LocalizedStringKey {
        switch self {
        case .reduceMotion: "theme.pageTurn.reduceMotion"
        case .reflowableText: "theme.pageTurn.reflowable"
        }
    }
}
