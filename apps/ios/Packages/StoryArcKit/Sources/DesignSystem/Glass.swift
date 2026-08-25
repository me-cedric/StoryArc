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
    /// Untinted, deliberately: the spec wants the glass to pick up the page
    /// beneath it, and a tint is precisely what stops it doing that.
    ///
    /// Group adjacent surfaces in a `GlassEffectContainer` so their shapes morph
    /// as one when they meet — the container is the only thing that produces that,
    /// and this modifier cannot do it from inside a single surface.
    public func storyArcGlass(in shape: some InsettableShape = Capsule()) -> some View {
        modifier(GlassChrome(shape: shape))
    }
}

private struct GlassChrome<ChromeShape: InsettableShape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.theme) private var theme

    let shape: ChromeShape

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
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
