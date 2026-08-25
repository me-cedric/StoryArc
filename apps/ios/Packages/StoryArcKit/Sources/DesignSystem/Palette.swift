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

    /// The chrome accent. Light theme uses the stronger variant because
    /// `brand.ember` at 70 % lightness does not clear 3:1 on paper.
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
        accent: StoryArcColor.Brand.ember,
        accentMuted: StoryArcColor.Brand.emberMuted
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
        accent: StoryArcColor.Brand.emberStrong,
        accentMuted: StoryArcColor.Brand.emberMuted
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
        accent: StoryArcColor.Brand.ember,
        accentMuted: StoryArcColor.Brand.emberMuted
    )

    /// The palette for a resolved scheme and appearance.
    ///
    /// The appearance is a parameter rather than read from the environment because a
    /// palette is a value: the same scheme yields a different palette under OLED Dark,
    /// and nothing about that is the environment's business.
    public static func resolved(
        for scheme: ColorScheme,
        appearance: AppearanceMode = .system
    ) -> Palette {
        if appearance.isTrueBlack { return .oledDark }
        return scheme == .dark ? .dark : .light
    }
}
