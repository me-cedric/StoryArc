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

    public init(preset: ThemePreset = .paper, deviations: Set<ThemeAxis> = []) {
        self.preset = preset
        self.deviations = deviations
    }

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
        ReadingTheme(preset: preset)
    }

    /// Records that an axis was moved.
    ///
    /// An axis that cannot reach the page is not recorded as a deviation: nothing
    /// changed, so calling the preset modified would be a lie the reader could see.
    public func deviating(on axis: ThemeAxis) -> ReadingTheme {
        guard isEffective(axis) else { return self }
        return ReadingTheme(preset: preset, deviations: deviations.union([axis]))
    }

    /// Puts every axis back to the preset's own values.
    public func restored() -> ReadingTheme {
        ReadingTheme(preset: preset)
    }
}
