import SwiftUI
import Testing

@testable import DesignSystem

/// The opaque fallback of the reader's glass buttons, measured — task 9.8.
///
/// The fallback is what a reader with Reduce Transparency or Increase Contrast sees, and the
/// HIG asks for a 44 by 44 pt target. `ImageRenderer` lays the style out on the host, so the
/// size is measured here, not read from the source.
@Suite("The reader's opaque glass-button fallback")
@MainActor
struct OpaqueChromeButtonStyleTests {

    private func size(of view: some View) -> CGSize {
        let renderer = ImageRenderer(content: view)
        var measured = CGSize.zero
        renderer.render { size, _ in measured = size }
        return measured
    }

    @Test("An icon-only button is at least 44 by 44 points")
    func iconOnlyMeetsTheTarget() {
        let button = Button {} label: { Image(systemName: "xmark") }
            .buttonStyle(OpaqueChromeButtonStyle(shape: Circle(), palette: .dark))
        let measured = size(of: button)
        #expect(measured.width >= 44)
        #expect(measured.height >= 44)
    }

    @Test("A text button keeps a margin inside its capsule")
    func textKeepsItsMargin() {
        let label = Text(verbatim: "Back to page 12")
        let bare = size(of: label)
        let styled = size(
            of: Button {} label: { label }
                .buttonStyle(OpaqueChromeButtonStyle(shape: Capsule(), palette: .dark))
        )
        #expect(styled.width >= bare.width + 2 * StoryArcSpace.md)
    }
}
