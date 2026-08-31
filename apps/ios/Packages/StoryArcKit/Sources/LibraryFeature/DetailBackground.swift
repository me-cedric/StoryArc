internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// The cover's colour, on the page's content and nowhere else.
///
/// Three rules from `publication-detail`, and each of them is here rather than at a call
/// site, because a rule that has to be remembered per screen is a rule that will be missing
/// from one of them:
///
/// - **It reaches content only.** This is a `.background` under the scroll view. Nothing
///   here tints the navigation bar, the tab bar or any floating chrome — `native-experience`
///   requires untinted glass, and a tab bar that changed hue as a reader moved between
///   publications is the exact failure the requirement was written against.
/// - **It fades out.** Strongest behind the artwork and gone by the foot of the page, so
///   the wash reads as light coming off the cover rather than as a coloured surface with an
///   edge. Only the strongest point was contrast-checked, so every point below it is safer
///   than the one that passed.
/// - **Increased contrast and reduced transparency replace it.** Not soften it. Softening a
///   wash is how a screen ends up marginally below the floor instead of clearly above it,
///   and a reader who asked for more contrast did not ask for a paler version of less.
/// - **It arrives rather than appearing.** The page is composed before its cover is decoded —
///   `PublicationDetailView` holds `nil` on the first frame for every publication, and for a
///   remote one that has not been downloaded the cover never arrives at all. So the wash
///   changes under a screen the reader is already looking at, and `publication-detail` task
///   0.1 requires that to happen with **no visible flash**. It was a hard cut: nothing in any
///   of the `Detail*.swift` files animated, while Android crossfaded the same change at
///   `DetailHero.kt:94`.
struct DetailBackground: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `nil` for a cover with no colour to give, which is the ordinary manga case.
    let wash: DetailWash?

    var body: some View {
        ZStack {
            theme.palette.surfaceCanvas
            // Always drawn, and faded by ``strength``, rather than held in an `if let`. A
            // view that is inserted has nothing to interpolate from, which is the whole
            // reason the arrival was a cut — and the arithmetic is unchanged, because an
            // opacity on the layer multiplies through its stops exactly as the strength used
            // to be baked into them. The one point that was contrast-checked is still the
            // one that is drawn at full strength.
            LinearGradient(
                stops: [
                    .init(color: tint, location: 0),
                    .init(color: tint.opacity(0.4), location: 0.35),
                    .init(color: .clear, location: 0.75),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(strength)
            // The crossfade Android has had. `nil` for a reader who asked for less motion:
            // a wash that snaps into place is still a legible page, and `native-experience`
            // is explicit that reduced motion removes an animation rather than shortening it.
            .animation(
                reduceMotion ? nil : .easeInOut(duration: StoryArcDuration.normal),
                value: strength
            )
        }
        .ignoresSafeArea()
        // Decoration, and labelled as nothing. It carries no meaning and nothing on the
        // page depends on it to be found, which is the delta's own wording.
        .accessibilityHidden(true)
    }

    /// How much wash this page draws right now. The rule is ``DetailWash/drawn(_:isPlain:)``.
    private var strength: Double { DetailWash.drawn(wash, isPlain: isPlain) }

    /// The colour it fades in, or a placeholder nothing ever sees at zero strength.
    private var tint: Color { Color(hex: wash?.tint ?? "#000000") }

    /// Whether the system has asked for a plain surface instead.
    private var isPlain: Bool { contrast == .increased || reduceTransparency }
}

extension Color {
    /// A `#rrggbb` string as a colour.
    ///
    /// The inverse of ``resolvedHex(in:)``, and the only way a colour derived from artwork
    /// reaches a view: ``CoverAccent`` and ``DetailWash`` both answer in hex because both
    /// are asserted by tests that have no SwiftUI to hand.
    init(hex: String) {
        let text = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let value = Int(text, radix: 16) ?? 0
        self = Color(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// This colour as `#rrggbb`, resolved against the environment it will be drawn in.
    ///
    /// The palette is a set of `Color`s and the contrast arithmetic works in hex, so
    /// something has to cross between them. Here rather than by adding a hex mirror to the
    /// generated tokens: the tokens are generated from `packages/design-tokens`, a second
    /// table of the same values would be a second thing to keep in step, and the resolved
    /// colour is the one that actually reaches the screen — including whatever the
    /// appearance and the contrast setting did to it on the way.
    func resolvedHex(in environment: EnvironmentValues) -> String {
        let resolved = resolve(in: environment)
        func channel(_ value: Float) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(
            format: "#%02X%02X%02X",
            channel(resolved.red),
            channel(resolved.green),
            channel(resolved.blue)
        )
    }
}
