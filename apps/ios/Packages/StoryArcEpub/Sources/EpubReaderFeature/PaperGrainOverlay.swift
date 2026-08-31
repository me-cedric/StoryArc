internal import SwiftUI

internal import DesignSystem

/// Natural's paper grain, over the page and nothing else.
///
/// `settings-and-about`: "reading surfaces gain a subtle paper grain… the texture is
/// disabled automatically when Reduce Transparency or Increase Contrast is on, because
/// grain lowers effective contrast". ``PaperGrain`` owns that rule; this draws the result.
///
/// A view rather than a modifier on the navigator, because it must sit *between* the page
/// and the chrome: grain belongs on the page, and a toolbar with paper texture behind its
/// glass is neither.
struct PaperGrainOverlay: View {
    @Environment(\.isNaturalTheme) private var isNatural
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    /// Points per pixel on this display, so a speck is one physical size everywhere.
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        if PaperGrain.isDrawn(
            natural: isNatural,
            reduceTransparency: reduceTransparency,
            contrast: contrast
        ) {
            Rectangle()
                .fill(
                    ShaderLibrary.bundle(.module).paperGrain(
                        .float(PaperGrain.cell(atDisplayScale: displayScale)),
                        .float(PaperGrain.intensity),
                        .float(PaperGrain.fineOctave)
                    )
                )
                .ignoresSafeArea()
                // A texture, not a target. Every tap belongs to the page underneath, and
                // the reader's turn gestures are registered on the navigator's own view.
                .allowsHitTesting(false)
                // And not a thing to describe. VoiceOver reading "image" over every page
                // would be worse than saying nothing at all.
                .accessibilityHidden(true)
        }
    }
}
