public import SwiftUI

public import StoryArcCore

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

    /// What to draw on ``coverAccent``, derived from that fill. A cover colour is the one fill
    /// no token gate can see, so the label is chosen for it at run time.
    public var coverOnAccent: Color?

    public var accent: Color { coverAccent ?? palette.accent }

    /// The accent drawn as text, at 4.5:1 or better: a borderless button, a link, the selected
    /// tab label. Under a cover accent that colour already clears the floor, so it serves both.
    public var accentText: Color { coverAccent ?? palette.accentText }

    /// The label or icon drawn on ``accent``, at 4.5:1 or better.
    public var onAccent: Color { coverOnAccent ?? palette.onAccent }

    public init(palette: Palette, coverAccent: Color? = nil, coverOnAccent: Color? = nil) {
        self.palette = palette
        self.coverAccent = coverAccent
        self.coverOnAccent = coverOnAccent
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
    /// - Parameter appearance: what the reader chose. `settings-and-about` requires it
    ///   to apply "immediately across the whole app without a restart", which is what
    ///   passing it through the environment gets for free.
    public func storyArcTheme(appearance: AppearanceMode = .system) -> some View {
        modifier(ThemeResolver(appearance: appearance))
            .preferredColorScheme(appearance.colorScheme)
    }

    /// Layers a cover-derived accent over the inherited theme for this subtree.
    public func coverAccent(_ color: Color?, label: Color? = nil) -> some View {
        transformEnvironment(\.theme) {
            $0.coverAccent = color
            $0.coverOnAccent = label
        }
    }

    /// Draws a label or icon in the colour made for the accent behind it. Put it on the
    /// content of a prominent button, whose fill is the accent and whose own label colour
    /// the system picks without knowing the fill.
    public func onAccentLabel() -> some View {
        modifier(OnAccentLabel())
    }
}

private struct OnAccentLabel: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content.foregroundStyle(theme.onAccent)
    }
}

private struct ThemeResolver: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    /// `native-experience`: Increase Contrast strengthens borders and the weakest text
    /// tier. Read once, here, so every screen below inherits the answer rather than
    /// each one asking the environment and deciding for itself what to do about it.
    @Environment(\.colorSchemeContrast) private var contrast
    /// Natural, read here rather than passed in. It is a second axis and not part of
    /// `AppSettings.appearance`, and reading it at the resolver keeps
    /// `storyArcTheme(appearance:)` a one-argument call at every site. See
    /// ``NaturalTheme``.
    @AppStorage(NaturalTheme.storageKey) private var isNatural = false

    let appearance: AppearanceMode

    func body(content: Content) -> some View {
        let theme = Theme(
            palette: .resolved(
                for: colorScheme,
                appearance: appearance,
                natural: isNatural,
                contrast: contrast
            )
        )
        return content
            .environment(\.theme, theme)
            // The environment tint is what a borderless button, a link and the selected tab label
            // draw as text, so it is the text accent. A prominent button fills with the accent
            // itself: it sets `.tint(theme.accent)` and `.onAccentLabel()` where it is drawn.
            .tint(theme.accentText)
            .background(theme.palette.surfaceCanvas)
            // `settings-and-about`: Natural's grain reaches reading surfaces and nothing
            // else, so what travels down the tree is the *permission*, not the texture.
            // The reader asks for it; the shelf and the settings list never do.
            .environment(\.isNaturalTheme, NaturalTheme.applies(isNatural, under: appearance))
    }
}

extension EnvironmentValues {
    /// Whether Natural is in force, for the reading surfaces that carry its grain.
    ///
    /// Separate from ``Theme`` because it is not a colour: every other screen resolves
    /// Natural entirely through the palette, and only a reading surface has anything
    /// more to do about it.
    @Entry public var isNaturalTheme = false
}
