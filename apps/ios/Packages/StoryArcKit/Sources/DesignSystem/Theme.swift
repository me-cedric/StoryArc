public import SwiftUI

/// The design system, injected once at the root and read anywhere below it.
///
/// Views read `\.theme` rather than reaching for ``StoryArcColor`` directly, so
/// that a cover-derived accent can be layered over the palette for one subtree
/// without every view knowing it happened.
public struct Theme: Sendable, Equatable {
    public var palette: Palette

    /// Set on a publication's detail screen and in the reader, derived from the
    /// cover art. `nil` everywhere else, where the brand accent is correct.
    ///
    /// `native-experience` requires a derived colour to be adjusted until it
    /// clears the contrast floor before it is used. Assigning a raw extracted
    /// colour here is a bug.
    public var coverAccent: Color?

    public var accent: Color { coverAccent ?? palette.accent }

    public init(palette: Palette, coverAccent: Color? = nil) {
        self.palette = palette
        self.coverAccent = coverAccent
    }
}

extension EnvironmentValues {
    /// Defaults to dark: the reader is the app's centre of gravity, and a
    /// missing injection should fail toward the theme most screens use.
    @Entry public var theme = Theme(palette: .dark)
}

extension View {
    /// Resolves the palette from the current colour scheme and injects it.
    /// Apply once, at the root.
    public func storyArcTheme() -> some View {
        modifier(ThemeResolver())
    }

    /// Layers a cover-derived accent over the inherited theme for this subtree.
    public func coverAccent(_ color: Color?) -> some View {
        transformEnvironment(\.theme) { $0.coverAccent = color }
    }
}

private struct ThemeResolver: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let theme = Theme(palette: .resolved(for: colorScheme))
        return content
            .environment(\.theme, theme)
            .tint(theme.accent)
            .background(theme.palette.surfaceCanvas)
    }
}
