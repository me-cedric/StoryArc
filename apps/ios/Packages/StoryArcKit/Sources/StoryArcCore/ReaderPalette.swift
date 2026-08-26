public import Foundation

/// WCAG contrast, and the two thresholds `reading-themes` cares about.
///
/// The same relative-luminance definition the token pipeline uses
/// (`packages/design-tokens/scripts/oklch.mjs`), down to the 0.04045 knee. If the
/// two drifted apart, a pairing could pass the build gate and be refused at
/// runtime, or worse the other way round.
public enum ReadingContrast {
    /// AAA body text. A derived text colour aims for this.
    public static let aaa = 7.0

    /// AA body text. Below this a pairing is refused outright.
    public static let aa = 4.5

    /// WCAG relative luminance of a `#rrggbb` colour, or nil if it is not one.
    public static func luminance(of hex: String) -> Double? {
        guard let channels = channels(of: hex) else { return nil }
        let linear = channels.map { channel -> Double in
            let value = Double(channel) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    }

    /// The contrast ratio between two colours, from 1 to 21.
    ///
    /// Returns 1 — the worst possible — for a colour it cannot read, rather than
    /// nil. A malformed hex should never be the reason a pairing is *accepted*.
    public static func ratio(_ one: String, _ other: String) -> Double {
        guard let first = luminance(of: one), let second = luminance(of: other) else { return 1 }
        let lighter = max(first, second)
        let darker = min(first, second)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// The most readable text colour for a background, and what it measures.
    ///
    /// Black or white, and nothing between them can do better: contrast depends
    /// only on relative luminance, and black and white are its extremes. So this is
    /// not a search that gave up early — it is the whole answer.
    ///
    /// A mid-tone background has no text colour that reaches AAA at all: grey
    /// `#808080` tops out near 5.3. The ratio comes back so a caller can say that
    /// rather than silently return something illegible.
    public static func bestForeground(on background: String) -> (hex: String, ratio: Double) {
        let black = ratio(background, "#000000")
        let white = ratio(background, "#FFFFFF")
        return black >= white ? ("#000000", black) : ("#FFFFFF", white)
    }

    private static func channels(of hex: String) -> [Int]? {
        var text = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        // `#abc` is a legal CSS colour and the pickers may hand one over.
        if text.count == 3 { text = text.map { "\($0)\($0)" }.joined() }
        guard text.count == 6, let value = Int(text, radix: 16) else { return nil }
        return [(value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF]
    }
}

/// A reading background and the text colour paired with it.
///
/// `reading-themes` requires a custom colour to be kept "as a seventh, user-named
/// slot alongside the six presets rather than overwriting one", so the name is part
/// of the value rather than a label attached elsewhere.
public struct ReaderPalette: Sendable, Equatable, Hashable, Codable {
    /// What the reader called it.
    public var name: String
    /// `#rrggbb`.
    public var background: String
    /// `#rrggbb`. Derived from the background unless the reader overrode it.
    public var foreground: String

    public init(name: String, background: String, foreground: String) {
        self.name = name
        self.background = background
        self.foreground = foreground
    }

    /// A palette for a background, with the most readable text colour derived.
    public static func derived(name: String, background: String) -> ReaderPalette {
        ReaderPalette(
            name: name,
            background: background,
            foreground: ReadingContrast.bestForeground(on: background).hex
        )
    }

    /// What this pairing measures.
    public var contrast: Double { ReadingContrast.ratio(background, foreground) }

    /// Whether this pairing may be used at all.
    ///
    /// `reading-themes`: a pairing below 4.5:1 "is refused with the measured ratio
    /// stated", because a refusal without a number is just an obstacle.
    public var isReadable: Bool { contrast >= ReadingContrast.aa }

    /// Whether it reaches the AAA level every built-in preset clears.
    public var meetsAAA: Bool { contrast >= ReadingContrast.aaa }

    /// The same palette with a different text colour, whether or not it is legible.
    ///
    /// Deliberately does not refuse: the sheet has to *show* the measured ratio of
    /// the pairing the reader tried, which it cannot do if the attempt is discarded
    /// before it exists. `isReadable` is what decides whether it may be applied.
    public func overriding(foreground: String) -> ReaderPalette {
        ReaderPalette(name: name, background: background, foreground: foreground)
    }
}

extension ReaderPalette {
    /// Backgrounds worth offering before the reader reaches for a picker.
    ///
    /// Not design tokens: a token is a colour the app uses, and these are starting
    /// points for a colour the *reader* chooses. They are here rather than in either
    /// UI so both platforms offer the same eight, and they are hex for the same
    /// reason the preset colours are — Readium parses its own.
    ///
    /// Every one of them clears AAA against black or white, so picking a swatch
    /// never lands the reader in the refusal path. The picker is where that can
    /// happen, which is the honest place for it.
    public static let suggestedBackgrounds = [
        "#FFFFFF",  // plain white, for a reader who wants no tint at all
        "#FBF0DA",  // cream
        "#F2E8DC",  // sepia
        "#E8EFE6",  // pale green, the classic eye-strain choice
        "#E6ECF5",  // pale blue
        "#2B2B2B",  // soft dark, easier than black on an LCD
        "#1B2430",  // deep navy
        "#000000",  // true black, which is the one an OLED panel rewards
    ]

    /// What each suggested background is called, keyed by its hex.
    ///
    /// Promoted from a code comment, because a comment is not something a screen
    /// reader can say. VoiceOver and TalkBack both read the swatch aloud, and both
    /// read "Colour #E8EFE6" one character at a time — which is not a colour a reader
    /// can pick from a row of eight.
    ///
    /// A key rather than a name: core carries no text a reader sees, so each UI turns
    /// the key into its own localised string. Here rather than in either UI so both
    /// platforms name the same colour the same thing.
    public static let suggestedBackgroundNames: [String: String] = [
        "#FFFFFF": "white",
        "#FBF0DA": "cream",
        "#F2E8DC": "sepia",
        "#E8EFE6": "sage",
        "#E6ECF5": "sky",
        "#2B2B2B": "charcoal",
        "#1B2430": "navy",
        "#000000": "trueBlack",
    ]

    /// Text colours worth offering when a reader overrides the derived one.
    ///
    /// Deliberately not only black and white. A warm dark on cream is a real
    /// preference, and some of these will fail against some backgrounds — which is
    /// the point: `reading-themes` requires the refusal to state its ratio, and a
    /// list that can never fail would leave that path untested by any real use.
    public static let suggestedForegrounds = [
        "#000000",
        "#2A2622",  // warm dark
        "#1B2430",  // cool dark
        "#FFFFFF",
        "#EDE6DA",  // warm light
        "#D8E0EA",  // cool light
    ]
}
