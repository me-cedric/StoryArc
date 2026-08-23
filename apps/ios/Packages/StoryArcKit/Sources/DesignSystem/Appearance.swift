public import SwiftUI

/// What the user chose in Settings › Appearance.
///
/// `settings-and-about` requires System, Light and Dark, defaulting to System,
/// applied without a restart. Reading themes are deliberately independent of
/// this — a dark chrome with a paper-white page is a legitimate preference.
public enum AppearanceMode: String, CaseIterable, Sendable, Codable {
    case system
    case light
    case dark

    /// `nil` lets SwiftUI follow the system, which is what `.system` means.
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    public var localizedNameKey: LocalizedStringKey {
        switch self {
        case .system: "appearance.system"
        case .light: "appearance.light"
        case .dark: "appearance.dark"
        }
    }
}
