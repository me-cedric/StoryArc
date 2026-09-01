public import SwiftUI

public import StoryArcCore

/// The resolved surface, text and border colours for one appearance.
///
/// Every value comes from ``StoryArcColor``, which is generated from
/// `packages/design-tokens`. Nothing here invents a colour; this type only
/// decides *which* generated colour a role resolves to for a given scheme.
public struct Palette: Sendable, Equatable {
    public let surfaceCanvas: Color
    public let surfaceRaised: Color
    public let surfaceOverlay: Color
    public let surfaceReader: Color
    public let surfaceSunken: Color
    public let borderSubtle: Color
    public let borderStrong: Color
    public let textPrimary: Color
    public let textSecondary: Color
    public let textTertiary: Color
    public let scrim: Color

    /// The chrome accent — **the same value on every appearance**, deliberately.
    ///
    /// Its predecessor was a pair, because the lighter variant did not clear 3:1 on
    /// paper. `brand.accent` clears the floor on both canvases, 4.06:1 on dark and
    /// 4.43:1 on light, which is why the palette takes the violet from the middle of the
    /// mark's arc rather than the pink at its first stop — the pink reaches 2.48:1 on
    /// paper and would need a second token to exist at all. So a light-only variant is
    /// absent here rather than forgotten: `pnpm tokens:check` gates both readings.
    public let accent: Color
    public let accentMuted: Color

    public static let dark = Palette(
        surfaceCanvas: StoryArcColor.Dark.surfaceCanvas,
        surfaceRaised: StoryArcColor.Dark.surfaceRaised,
        surfaceOverlay: StoryArcColor.Dark.surfaceOverlay,
        surfaceReader: StoryArcColor.Dark.surfaceReader,
        surfaceSunken: StoryArcColor.Dark.surfaceSunken,
        borderSubtle: StoryArcColor.Dark.borderSubtle,
        borderStrong: StoryArcColor.Dark.borderStrong,
        textPrimary: StoryArcColor.Dark.textPrimary,
        textSecondary: StoryArcColor.Dark.textSecondary,
        textTertiary: StoryArcColor.Dark.textTertiary,
        scrim: StoryArcColor.Dark.scrim,
        accent: StoryArcColor.Brand.accent,
        accentMuted: StoryArcColor.Brand.accentMuted
    )

    public static let light = Palette(
        surfaceCanvas: StoryArcColor.Light.surfaceCanvas,
        surfaceRaised: StoryArcColor.Light.surfaceRaised,
        surfaceOverlay: StoryArcColor.Light.surfaceOverlay,
        surfaceReader: StoryArcColor.Light.surfaceReader,
        surfaceSunken: StoryArcColor.Light.surfaceSunken,
        borderSubtle: StoryArcColor.Light.borderSubtle,
        borderStrong: StoryArcColor.Light.borderStrong,
        textPrimary: StoryArcColor.Light.textPrimary,
        textSecondary: StoryArcColor.Light.textSecondary,
        textTertiary: StoryArcColor.Light.textTertiary,
        scrim: StoryArcColor.Light.scrim,
        accent: StoryArcColor.Brand.accent,
        accentMuted: StoryArcColor.Brand.accentMuted
    )

    /// True black chrome, with the reader surface deliberately above it.
    ///
    /// Every value comes from the generated `oledDark` tokens, including the reader
    /// surface that refuses to be `#000` — the reason is in `color.json` and not
    /// repeated here, because a reason in two places drifts.
    public static let oledDark = Palette(
        surfaceCanvas: StoryArcColor.OledDark.surfaceCanvas,
        surfaceRaised: StoryArcColor.OledDark.surfaceRaised,
        surfaceOverlay: StoryArcColor.OledDark.surfaceOverlay,
        surfaceReader: StoryArcColor.OledDark.surfaceReader,
        surfaceSunken: StoryArcColor.OledDark.surfaceSunken,
        borderSubtle: StoryArcColor.OledDark.borderSubtle,
        borderStrong: StoryArcColor.OledDark.borderStrong,
        textPrimary: StoryArcColor.OledDark.textPrimary,
        textSecondary: StoryArcColor.OledDark.textSecondary,
        textTertiary: StoryArcColor.OledDark.textTertiary,
        scrim: StoryArcColor.OledDark.scrim,
        accent: StoryArcColor.Brand.accent,
        accentMuted: StoryArcColor.Brand.accentMuted
    )

    /// The palette for a resolved scheme and appearance.
    ///
    /// The appearance is a parameter rather than read from the environment because a
    /// palette is a value: the same scheme yields a different palette under OLED Dark,
    /// and nothing about that is the environment's business. Contrast is a parameter
    /// for the same reason, and because it is the one thing about a palette a *test*
    /// has to be able to set.
    ///
    /// - Parameter natural: whether the reader chose Natural. A second axis rather than
    ///   a fifth appearance — see ``NaturalTheme``. It crosses light and dark rather
    ///   than replacing them, which is what "carries its own light and dark variants"
    ///   means, and OLED Dark declines it for the reason on `NaturalTheme.isAvailable`.
    public static func resolved(
        for scheme: ColorScheme,
        appearance: AppearanceMode = .system,
        natural: Bool = false,
        contrast: ColorSchemeContrast = .standard
    ) -> Palette {
        let isDark = scheme == .dark
        let base: Palette = if appearance.isTrueBlack {
            .oledDark
        } else if NaturalTheme.applies(natural, under: appearance) {
            isDark ? .naturalDark : .naturalLight
        } else {
            isDark ? .dark : .light
        }
        return contrast == .increased ? base.strengthened : base
    }

    /// The same palette with the roles Increase Contrast asks to strengthen.
    ///
    /// `native-experience`: with Increase Contrast on, "borders are strengthened". This
    /// is where that happens — once, in the tokens, rather than in each view deciding
    /// for itself what "stronger" means and half of them forgetting.
    ///
    /// Two roles move, and no colour is invented: the subtle border becomes the strong
    /// one, and the tertiary text tier steps up to secondary. Secondary deliberately
    /// does *not* step up to primary — with three tiers, promoting both would leave one
    /// tier, and a hierarchy flattened to nothing is not more legible.
    public var strengthened: Palette {
        Palette(
            surfaceCanvas: surfaceCanvas,
            surfaceRaised: surfaceRaised,
            surfaceOverlay: surfaceOverlay,
            surfaceReader: surfaceReader,
            surfaceSunken: surfaceSunken,
            borderSubtle: borderStrong,
            borderStrong: borderStrong,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            textTertiary: textSecondary,
            scrim: scrim,
            accent: accent,
            accentMuted: accentMuted
        )
    }
}
