public import SwiftUI

/// What the user chose in Settings › Appearance.
///
/// `settings-and-about` requires System, Light, Dark and OLED Dark, defaulting to
/// System, applied without a restart. Reading themes are deliberately independent of
/// this — a dark chrome with a paper-white page is a legitimate preference, and the
/// spec says so.
///
/// Natural is deliberately *not* a case here. The spec calls it "a theme rather than
/// an appearance… carries its own light and dark variants", so it sits alongside this
/// polarity rather than inside it. Putting it here would force a choice between
/// Natural and dark mode that the spec exists to avoid.
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

    /// `nil` lets SwiftUI follow the system, which is what `.system` means.
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark, .oledDark: .dark
        }
    }

    /// Whether this appearance wants the true-black palette rather than the warm one.
    public var isTrueBlack: Bool { self == .oledDark }

    public var localizedNameKey: LocalizedStringKey {
        switch self {
        case .system: "appearance.system"
        case .light: "appearance.light"
        case .dark: "appearance.dark"
        case .oledDark: "appearance.oledDark"
        }
    }

    /// The one-line reason a setting needs when it is not what its name implies.
    ///
    /// `settings-and-about`: OLED Dark is "honoured where it helps and explained where
    /// it does not". `nil` for the appearances that need no explanation.
    public var localizedNoteKey: LocalizedStringKey? {
        self == .oledDark ? "appearance.oledDark.note" : nil
    }
}
