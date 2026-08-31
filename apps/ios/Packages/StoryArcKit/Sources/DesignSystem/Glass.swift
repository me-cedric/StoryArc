public import SwiftUI

extension View {
    /// Liquid Glass, with the opaque fallback `native-experience` requires.
    ///
    /// The spec asks for two things that are easy to separate and should not be:
    /// floating chrome on Liquid Glass, and "every translucent chrome surface is
    /// replaced by its declared opaque fill" with "borders strengthened" when
    /// Reduce Transparency is on. Both live here, in one modifier, because a
    /// fallback that has to be remembered at every call site is a fallback that
    /// will be missing at one of them.
    ///
    /// Increase Contrast takes the same fallback. `native-experience` names the two
    /// settings in one breath — "WHEN Increase Contrast or Reduce Transparency is on" —
    /// and it is right to: glass over a page is a low-contrast surface whichever of the
    /// two the reader turned on to say so.
    ///
    /// Untinted, deliberately: the spec wants the glass to pick up the page
    /// beneath it, and a tint is precisely what stops it doing that.
    ///
    /// Group adjacent surfaces in a `GlassEffectContainer` so their shapes morph
    /// as one when they meet — the container is the only thing that produces that,
    /// and this modifier cannot do it from inside a single surface.
    public func storyArcGlass(in shape: some InsettableShape = Capsule()) -> some View {
        modifier(GlassChrome(shape: shape))
    }

    /// The foreground style for text drawn *on* ``storyArcGlass``.
    ///
    /// **A fixed colour cannot sit on this material, and one had been sitting on it.** Glass
    /// is untinted on purpose — `design.md` §5: "Chrome glass is untinted so it picks up the
    /// cover art beneath it" — so its luminance is whatever happens to be scrolling past.
    /// A `theme.palette` colour is a constant and cannot follow, and no text token is gated
    /// against glass in the first place: `pnpm tokens:check` measures the three text roles on
    /// `surfaceCanvas`, `surfaceRaised` and `surfaceSunken`, none of which this is.
    ///
    /// Found on a booted iPhone 17 Pro at `accessibility-extra-extra-extra-large`, where the
    /// covers are large enough that the library's bottom strip always sits over one: in light
    /// mode the scan summary was dark grey over glass that had picked up a dark purple cover,
    /// and very nearly invisible. In dark mode at the same size it read fine, which is the
    /// tell — the text was not following the material, and half the time the material moved
    /// the wrong way.
    ///
    /// A hierarchical style does follow it. `.primary` and `.secondary` resolve against the
    /// material rather than against a stored sRGB value, which is how the system's own tab
    /// bar labels stay legible in the same strip. Tinting the glass to make a fixed colour
    /// work is what `design.md` forbids, and inventing a token would be certifying a surface
    /// whose ground is unknowable.
    ///
    /// Under Reduce Transparency or Increase Contrast the ground *is* knowable — the modifier
    /// above swaps in `surfaceOverlay` — so the app's own neutral comes back with it, and the
    /// two halves stay in one place for the reason ``storyArcGlass`` gives.
    public func storyArcGlassText(_ level: GlassTextLevel = .secondary) -> some View {
        modifier(GlassText(level: level))
    }
}

/// How much of the reader's attention text on glass is asking for.
///
/// Two, matching the two the palette's chrome text actually used: the thing being said and
/// the quieter note beside it. A third would be a tertiary role on a surface where even the
/// secondary one could not be measured.
public enum GlassTextLevel: Sendable {
    case primary
    case secondary
}

private struct GlassText: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.theme) private var theme

    let level: GlassTextLevel

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content.foregroundStyle(
                level == .primary ? theme.palette.textPrimary : theme.palette.textSecondary
            )
        } else {
            content.foregroundStyle(level == .primary ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        }
    }
}

private struct GlassChrome<ChromeShape: InsettableShape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.theme) private var theme

    let shape: ChromeShape

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            // `surfaceOverlay` is the generated token for exactly this: a chrome
            // surface that has to be opaque. The stronger border is the second half
            // of the requirement — an opaque pill with a subtle edge disappears
            // into a page of the same lightness.
            content
                .background(theme.palette.surfaceOverlay, in: shape)
                .overlay(shape.strokeBorder(theme.palette.borderStrong, lineWidth: 1))
        } else {
            content.glassEffect(.regular, in: shape)
        }
    }
}
