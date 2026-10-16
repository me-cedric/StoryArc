import DesignSystem
import StoryArcCore
import SwiftUI

extension View {
    /// What every window carries: the design system's theme for the chosen appearance, the
    /// reader's own text size, the chrome accent, and the chosen language.
    ///
    /// `desktop-experience`: light and dark follow the system without a restart (the theme
    /// reads the colour scheme live), the accent is the brand colour unless the reader chose
    /// the system's, and macOS has no system text size so the app's own control scales every
    /// window. Task 2.23.
    func macChrome() -> some View {
        modifier(MacChrome())
    }
}

private struct MacChrome: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let settings = MacSettings.shared
        let accent = AccentModel.shared
        let palette = Palette.resolved(settings.settings.appearance, colorScheme)
        content
            .storyArcTheme(appearance: settings.settings.appearance)
            .tint(accent.chromeColour(for: settings.accent, brand: palette.accent))
            .dynamicTypeSize(settings.textSize.dynamicTypeSize)
            .preferredColorScheme(settings.settings.appearance.colorScheme)
            .environment(\.locale, Locale.storyArc)
    }
}

extension Palette {
    /// The palette the theme resolves for this appearance in this scheme.
    static func resolved(_ appearance: AppearanceMode, _ scheme: ColorScheme) -> Palette {
        switch appearance {
        case .light: .light
        case .dark: .dark
        case .oledDark: .oledDark
        case .system: scheme == .dark ? .dark : .light
        }
    }
}
