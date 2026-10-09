public import SwiftUI

extension View {
    /// Takes the layout and the touch area of a label to 44 pt, for a label that draws nothing of
    /// its own behind it: a row of text, an icon, a swatch under `.buttonStyle(.plain)`.
    ///
    /// **Not for a `.bordered` or `.glass` button.** The system draws that capsule around the
    /// label, so a 44 pt label makes a 44 pt capsule. Those buttons take
    /// ``HitRegionButtonStyle`` instead, which grows the touch area around the system capsule.
    public func hitRegion(alignment: Alignment = .center) -> some View {
        frame(minWidth: 44, minHeight: 44, alignment: alignment)
            .contentShape(.rect)
    }
}

/// A system button style whose touch area is 44 by 44 pt while the drawn control keeps its
/// system size (decision O31 of `close-the-audited-gaps`).
///
/// `.buttonStyle(.bordered)` draws a 28 pt capsule at the small control size. A frame on its
/// label grows the capsule, and a content shape on its label stops at the capsule's edge: the
/// style clips the hit test to its own body. So the style draws the system button as it is,
/// reserves 44 pt around it, and forwards a tap in the reserved margin to the same action.
/// Taps inside the capsule reach the system button, which keeps its pressed state.
///
/// The margin is out of the accessibility tree: VoiceOver has the one button, whose frame is
/// the 44 pt that the platform's hit-region audit measures.
public struct HitRegionButtonStyle<Base: PrimitiveButtonStyle>: PrimitiveButtonStyle {
    private let base: Base

    public init(_ base: Base) {
        self.base = base
    }

    public func makeBody(configuration: Configuration) -> some View {
        HitRegionButton(base: base, configuration: configuration)
    }
}

private struct HitRegionButton<Base: PrimitiveButtonStyle>: View {
    @Environment(\.isEnabled) private var isEnabled

    let base: Base
    let configuration: PrimitiveButtonStyleConfiguration

    var body: some View {
        Button(configuration)
            .buttonStyle(base)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.accessibility, .rect)
            .background {
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture(perform: configuration.trigger)
                    .allowsHitTesting(isEnabled)
                    .accessibilityHidden(true)
            }
    }
}
