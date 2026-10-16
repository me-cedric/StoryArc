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
            .scaledFont(.body)
            .controlSize(settings.textSize == .default ? .regular : .large)
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

extension Font.TextStyle {
    /// The point size macOS 26 draws each text style at, from the system's own table.
    var macPointSize: CGFloat {
        switch self {
        case .largeTitle: 26
        case .title: 22
        case .title2: 17
        case .title3: 15
        case .headline, .body: 13
        case .callout: 12
        case .subheadline: 11
        case .footnote, .caption: 10
        case .caption2: 10
        @unknown default: 13
        }
    }

    /// The weight macOS gives a text style when none is asked for.
    var macWeight: Font.Weight { self == .headline ? .bold : .regular }
}

extension View {
    /// A text style at the size the reader chose in Appearance, which macOS does not do for an app.
    func scaledFont(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> some View {
        modifier(ScaledFont(style: style, weight: weight))
    }
}

private struct ScaledFont: ViewModifier {
    let style: Font.TextStyle
    let weight: Font.Weight?

    func body(content: Content) -> some View {
        let size = style.macPointSize * MacSettings.shared.textSize.scale
        content.font(.system(size: size, weight: weight ?? style.macWeight))
    }
}
