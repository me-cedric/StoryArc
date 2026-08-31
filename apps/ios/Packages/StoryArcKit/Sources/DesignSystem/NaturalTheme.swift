public import SwiftUI

public import StoryArcCore

/// Natural: the app's third appearance axis, and deliberately not a fourth
/// ``AppearanceMode`` case.
///
/// `settings-and-about` calls Natural "a theme rather than an appearance… carries its
/// own light and dark variants". Both halves of that sentence are load-bearing:
///
/// - **Not a case in ``AppearanceMode``.** That enum is the *polarity* axis — which end
///   of light and dark the app sits at, or that it follows the device. A fifth case
///   there would make Natural and dark mode alternatives, which is exactly the choice
///   the spec exists to avoid. `AppearanceModeTests` and Android's `AppearanceTest`
///   both assert its absence so a later hand does not helpfully add it.
/// - **Not a reading theme either.** A `ThemePreset` reaches the page and stops there.
///   Natural's warm accents reach the library, settings and the source list, because
///   `design.md` decided they do: "the theme is coherent rather than bolted onto the
///   reader".
///
/// So it is a second axis crossed with the first: three of the four appearances × on
/// or off. System, Light and Dark each gain a Natural variant; OLED Dark does not, for
/// the reason on ``isAvailable(under:)``.
///
/// ## Where the choice is stored
///
/// Its own key, read by the design system rather than a field on `AppSettings`. Two
/// reasons, and the second is the honest one:
///
/// 1. `AppSettings.appearance` answers "which polarity". Natural answers "which
///    texture". Storing an independent axis inside the field it is independent of is
///    how a boolean ends up encoded in an enum a year later.
/// 2. It is read *here*, inside `ThemeResolver`, so `storyArcTheme(appearance:)` keeps
///    its signature and every call site in the app target is untouched. `ReaderPreferences`
///    already sets the precedent that a preference can live outside `AppSettings` when
///    the type that reads it is not the settings screen.
public enum NaturalTheme {
    /// Where the choice is stored, read by ``ThemeResolver`` and written by the
    /// Appearance screen. One constant, so the two cannot disagree about the key.
    public static let storageKey = "storyarc.appearance.natural"

    /// Whether Natural can be combined with this appearance.
    ///
    /// False for OLED Dark alone. Warm cream stock and true black are contradictory
    /// asks, and OLED Dark's whole reason is a promise about the black point on a
    /// panel — a Natural canvas at `#16100C` would quietly break it. The Appearance
    /// screen therefore shows the switch *unavailable with the reason* rather than
    /// hiding it or leaving a live control that does nothing, which is the same shape
    /// `reading-themes` requires of an axis that cannot reach the page.
    public static func isAvailable(under appearance: AppearanceMode) -> Bool {
        !appearance.isTrueBlack
    }

    /// Whether Natural actually applies, given what the reader chose and where.
    ///
    /// The one place the two axes are combined, so no view has to remember that
    /// OLED Dark wins.
    public static func applies(_ isOn: Bool, under appearance: AppearanceMode) -> Bool {
        isOn && isAvailable(under: appearance)
    }
}

extension Palette {
    /// Warm cream stock and an earthier accent. Natural's light variant.
    ///
    /// The accent is `clayStrong` for the reason light uses `emberStrong`: clay at 66 %
    /// lightness does not clear 3:1 on warm paper. `pnpm tokens:check` gates that pair.
    ///
    /// `accentMuted` is the same value rather than a `clayMuted` that does not exist.
    /// Its only reader is the settings-search highlight, which draws it at 30 % alpha,
    /// and inventing a token no contrast gate covers to serve one wash is a worse trade
    /// than an accent at rest that happens to equal the accent.
    public static let naturalLight = Palette(
        surfaceCanvas: StoryArcColor.NaturalLight.surfaceCanvas,
        surfaceRaised: StoryArcColor.NaturalLight.surfaceRaised,
        surfaceOverlay: StoryArcColor.NaturalLight.surfaceOverlay,
        surfaceReader: StoryArcColor.NaturalLight.surfaceReader,
        surfaceSunken: StoryArcColor.NaturalLight.surfaceSunken,
        borderSubtle: StoryArcColor.NaturalLight.borderSubtle,
        borderStrong: StoryArcColor.NaturalLight.borderStrong,
        textPrimary: StoryArcColor.NaturalLight.textPrimary,
        textSecondary: StoryArcColor.NaturalLight.textSecondary,
        textTertiary: StoryArcColor.NaturalLight.textTertiary,
        scrim: StoryArcColor.NaturalLight.scrim,
        accent: StoryArcColor.Brand.clayStrong,
        accentMuted: StoryArcColor.Brand.clayStrong
    )

    /// Warm ink and the clay accent. Natural's dark variant.
    ///
    /// The reader surface goes deeper than the canvas here, as it does in every other
    /// palette: the page is meant to be the brightest thing on a light appearance and
    /// the deepest on a dark one, and grain is drawn *over* it rather than instead of it.
    public static let naturalDark = Palette(
        surfaceCanvas: StoryArcColor.NaturalDark.surfaceCanvas,
        surfaceRaised: StoryArcColor.NaturalDark.surfaceRaised,
        surfaceOverlay: StoryArcColor.NaturalDark.surfaceOverlay,
        surfaceReader: StoryArcColor.NaturalDark.surfaceReader,
        surfaceSunken: StoryArcColor.NaturalDark.surfaceSunken,
        borderSubtle: StoryArcColor.NaturalDark.borderSubtle,
        borderStrong: StoryArcColor.NaturalDark.borderStrong,
        textPrimary: StoryArcColor.NaturalDark.textPrimary,
        textSecondary: StoryArcColor.NaturalDark.textSecondary,
        textTertiary: StoryArcColor.NaturalDark.textTertiary,
        scrim: StoryArcColor.NaturalDark.scrim,
        accent: StoryArcColor.Brand.clay,
        accentMuted: StoryArcColor.Brand.clayStrong
    )
}

extension AppearanceMode {
    /// The one-line reason the Natural switch is unavailable under this appearance,
    /// or `nil` where it is available.
    public var naturalUnavailableKey: LocalizedStringKey? {
        NaturalTheme.isAvailable(under: self) ? nil : "appearance.natural.unavailable"
    }
}
