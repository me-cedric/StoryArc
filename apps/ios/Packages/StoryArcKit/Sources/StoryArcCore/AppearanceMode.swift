public import Foundation

/// What the reader chose in Settings › Appearance.
///
/// `settings-and-about` requires System, Light, Dark and OLED Dark, defaulting to
/// System, applied without a restart. Reading themes are deliberately independent of
/// this — a dark chrome with a paper-white page is a legitimate preference, and the
/// spec says so.
///
/// Natural is deliberately *not* a case. The spec calls it "a theme rather than an
/// appearance… carries its own light and dark variants", so it sits alongside this
/// polarity rather than inside it. Putting it here would force a choice between
/// Natural and dark mode that the spec exists to avoid.
///
/// In the domain rather than the design system, because it is a *setting*: it is
/// stored, it is one of the values `AppSettings` carries, and the mapping to a
/// `ColorScheme` and a palette is the design system's business rather than its
/// definition. The same split `ReaderTypeface` already uses.
public enum AppearanceMode: String, CaseIterable, Sendable, Codable {
    case system
    case light
    case dark
    /// True black chrome, for OLED panels where black draws no power.
    ///
    /// The reader surface stays *above* true black even here. Pure black smears on
    /// OLED during a page turn, which is the exact motion this app is built around —
    /// so the setting is honoured where it helps and the palette declines it where it
    /// does not. The generated `oledDark` tokens carry that decision, not this type.
    case oledDark

    /// Whether this appearance wants the true-black palette rather than the warm one.
    public var isTrueBlack: Bool { self == .oledDark }
}

public extension ThemePreset {
    /// The reading theme that goes with an app appearance.
    ///
    /// `settings-and-about` keeps the two apart by default — "a dark app chrome with a
    /// paper-white page is a legitimate preference" — and then allows "a single opt-in
    /// setting" that links them. This is the mapping that setting uses.
    ///
    /// Two presets, not four. Light is Paper and every dark appearance is Quiet, because
    /// the difference between Dark and OLED Dark is the *chrome*'s black point and a
    /// reading surface is deliberately never pure black anyway. Mapping OLED Dark to a
    /// darker reading theme would undo the reason that appearance exists.
    ///
    /// System resolves to whichever the device is showing, so it is the caller's job to
    /// pass the resolved appearance rather than `.system` — there is no answer for
    /// "follow the device" here, only for what the device currently says.
    static func matching(_ appearance: AppearanceMode) -> ThemePreset {
        switch appearance {
        case .light: .paper
        case .dark, .oledDark: .quiet
        // A caller that has not resolved System gets the light answer rather than a
        // crash. Documented rather than silent: `.system` is a question, not a value.
        case .system: .paper
        }
    }
}
