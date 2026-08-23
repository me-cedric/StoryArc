public import SwiftUI

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

    public static func resolved(for scheme: ColorScheme) -> Palette {
        scheme == .dark ? .dark : .light
    }
}
