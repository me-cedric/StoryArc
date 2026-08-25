public import SwiftUI

public import StoryArcCore

// How an appearance reaches SwiftUI. The enum itself is a setting and lives in
// `StoryArcCore`; this is the part that is the design system's business.
extension AppearanceMode {
    /// `nil` lets SwiftUI follow the system, which is what `.system` means.
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark, .oledDark: .dark
        }
    }

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
