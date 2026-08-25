public import Foundation

/// The named reading themes.
///
/// `reading-themes` lists six, and they are not the four the main `ebook-reader`
/// spec used to name — this change replaces Paper/Sepia/Night/High Contrast with a
/// set that includes *Original*, which is the one that could not be expressed
/// before. Original is not a colour scheme; it is the absence of one.
///
/// The colours themselves live in `packages/design-tokens/tokens/color.json` under
/// `readingThemes`, so all six go through the existing AAA contrast gate and a
/// preset that fails 7:1 fails the build.
public enum ThemePreset: String, Sendable, Codable, CaseIterable {
    /// The publication as its publisher styled it.
    case original
    /// Low-contrast dark: soft off-white on deep neutral, tightened spacing.
    case quiet
    /// Neutral light: book-stock white, serif, comfortable spacing.
    case paper
    /// High contrast, heavier weight, wider spacing. Low vision without leaving
    /// the aesthetic.
    case bold
    /// Warm dim: cream on brown, generous line height. Long evening sessions.
    case calm
    /// Narrow measure, high contrast, minimal decoration. Fewest words per line.
    case focus

    /// Whether the publication's own stylesheet stays in force.
    ///
    /// True for `original` alone, and it is what makes seven of the nine axes
    /// inert under it. `reading-themes` requires those controls to say so rather
    /// than sit there doing nothing.
    public var keepsPublisherStyles: Bool { self == .original }
}

/// The axes a reading theme is made of.
///
/// Exactly the list in `reading-themes`, and each one carries the fact that
/// decides whether its control is usable: whether Readium can apply it while the
/// publisher's stylesheet is still in force. That is a property of the axis, not of
/// the UI, which is why it lives here.
public enum ThemeAxis: String, Sendable, Codable, CaseIterable {
    case fontSize
    case fontFamily
    case boldText
    case lineSpacing
    case characterSpacing
    case wordSpacing
    case paragraphSpacing
    case margins
    case textAlignment

    /// Whether this axis needs the publisher's stylesheet switched off.
    ///
    /// From `design.md`'s mapping table, which is Readium's behaviour rather than
    /// ours: font size, family, weight and margins reach the page regardless;
    /// spacing and alignment are overridden by publisher CSS.
    public var requiresPublisherStylesOff: Bool {
        switch self {
        case .fontSize, .fontFamily, .boldText, .margins: false
        case .lineSpacing, .characterSpacing, .wordSpacing, .paragraphSpacing, .textAlignment: true
        }
    }
}

/// A preset, plus wherever the reader has since departed from it.
///
/// Deliberately holds no typographic *values*. A preset is a named
/// `EPUBPreferences` value and Readium owns those (`design.md`: "no preset
/// machinery to build"). What the app has to know, and Readium will not tell it,
/// is which preset was chosen and which axes the reader has moved since — because
/// `reading-themes` requires a deviated preset to stay selected and be "marked as
/// modified", with one action to put it back.
public struct ReadingTheme: Sendable, Equatable, Codable {
    public var preset: ThemePreset
    /// The axes moved since the preset was adopted.
    public var deviations: Set<ThemeAxis>

    /// The reader's own colours, when they have chosen some.
    ///
    /// `reading-themes` requires a custom colour to be "a seventh, user-named slot
    /// alongside the six presets rather than overwriting one" — so it sits beside
    /// `preset` instead of being one of its cases. The preset still supplies the
    /// typography: choosing a background is a decision about colour, and it should
    /// not silently reset the line height the reader spent a minute on.
    public var custom: ReaderPalette?

    public init(
        preset: ThemePreset = .paper,
        deviations: Set<ThemeAxis> = [],
        custom: ReaderPalette? = nil
    ) {
        self.preset = preset
        self.deviations = deviations
        self.custom = custom
    }

    /// Whether the reader's own colours are in force.
    public var isCustom: Bool { custom != nil }

    /// Whether to mark the preset as modified rather than plainly active.
    public var isModified: Bool { !deviations.isEmpty }

    /// Whether an axis can reach the page at all.
    ///
    /// `reading-themes`: under Original the dependent axes are "shown as
    /// unavailable with a one-line explanation, not hidden and not shown as dead
    /// controls". Hidden loses the explanation; a live-looking control that does
    /// nothing is worse than either.
    public func isEffective(_ axis: ThemeAxis) -> Bool {
        !(preset.keepsPublisherStyles && axis.requiresPublisherStylesOff)
    }

    /// The axes a reader can actually move under this preset.
    public var effectiveAxes: [ThemeAxis] {
        ThemeAxis.allCases.filter(isEffective)
    }

    /// Adopts a preset, which discards any deviation from the last one.
    ///
    /// `reading-themes`: tapping a preset applies "every axis the preset defines
    /// ... at once". Carrying a previous deviation across would mean the preset the
    /// reader just tapped is not the one they get.
    public func adopting(_ preset: ThemePreset) -> ReadingTheme {
        // The custom colours go with it. Tapping one of the six is how a reader
        // leaves their own palette, and a preset that kept a custom background
        // would not be the preset they tapped.
        ReadingTheme(preset: preset)
    }

    /// Puts the reader's own colours in force, keeping the typography they have.
    ///
    /// Kept separate from `adopting` for the reason the spec gives: the custom slot
    /// sits alongside the six rather than replacing one of them, so choosing it is
    /// not the same act as choosing a preset. It also cannot be chosen under
    /// Original, where the publisher's own colours are the point.
    public func adopting(_ palette: ReaderPalette) -> ReadingTheme {
        guard !preset.keepsPublisherStyles else { return self }
        return ReadingTheme(preset: preset, deviations: deviations, custom: palette)
    }

    /// Drops the reader's own colours and goes back to the preset's.
    public func discardingCustomColours() -> ReadingTheme {
        ReadingTheme(preset: preset, deviations: deviations)
    }

    /// Records that an axis was moved.
    ///
    /// An axis that cannot reach the page is not recorded as a deviation: nothing
    /// changed, so calling the preset modified would be a lie the reader could see.
    public func deviating(on axis: ThemeAxis) -> ReadingTheme {
        guard isEffective(axis) else { return self }
        return ReadingTheme(preset: preset, deviations: deviations.union([axis]), custom: custom)
    }

    /// Puts every axis back to the preset's own values, and its colours with them.
    public func restored() -> ReadingTheme {
        ReadingTheme(preset: preset)
    }
}
