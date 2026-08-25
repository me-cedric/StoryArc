internal import CoreGraphics
internal import SwiftUI

internal import StoryArcCore

/// A page being turned by the finger.
///
/// `page-transitions` asks for four things that are one gesture: the page follows the
/// finger in real time; past halfway the turn completes and before it the page springs
/// back; a flick completes regardless of distance; and a new drag during the settle
/// takes over from where the page is rather than snapping.
///
/// The shader is the twin of Android's AGSL, down to the constants — `design.md` calls
/// for one projection "expressed twice rather than solved twice".
struct CurledPages: View {
    /// The page being turned away.
    let page: CGImage?
    /// The page underneath it, or `nil` at the last page.
    let beneath: CGImage?
    let isRightToLeft: Bool
    /// Called once a turn has completed.
    let onTurned: () -> Void
    /// A press that was not a drag: the caller decides what it means.
    let onTap: (CGPoint, CGSize) -> Void

    /// 0 while the page is flat, 1 when it has fully turned.
    @State private var progress: Double = 0
    /// What the drag had reached when it ended, kept so the release decision does not
    /// depend on where an in-flight animation happens to be.
    @State private var reached: Double = 0

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                // Black behind, because the shader leaves the letterbox transparent
                // rather than smearing the page's edge pixel across it. A comic is
                // read against its own artwork, not against a themed surface.
                Color.black

                if let page {
                    Rectangle()
                        .fill(shader(for: page, in: size))
                }
            }
            .contentShape(.rect)
            .gesture(turnGesture(in: size))
            .onTapGesture { location in onTap(location, size) }
        }
    }

    // MARK: - The shader

    private func shader(for page: CGImage, in size: CGSize) -> Shader {
        ShaderLibrary.bundle(.module).pageCurl(
            .float(progress),
            .float(Self.crease),
            .float(Self.shadow),
            .float(isRightToLeft ? -1 : 1),
            .float(Self.back),
            .float2(size.width, size.height),
            .image(Image(decorative: page, scale: 1)),
            // The outgoing page stands in for a missing one, so the last page still
            // turns rather than tearing to nothing. Whether it *may* turn is the
            // caller's business, not the shader's.
            .image(Image(decorative: beneath ?? page, scale: 1))
        )
    }

    // MARK: - The gesture

    private func turnGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                // Turn-space: a right-to-left publication turns forward when the finger
                // moves the other way, so one sign carries the whole mirroring.
                let forward = isRightToLeft ? value.translation.width : -value.translation.width
                reached = min(max(forward / size.width, 0), 1)
                // No animation on the drag itself: the page follows the finger, and an
                // animation between finger positions is a page lagging behind it.
                progress = reached
            }
            .onEnded { value in
                // Past halfway it completes; before it, it springs back. A flick
                // completes whatever the distance, because a fast finger has already
                // said what it meant.
                let velocity = isRightToLeft
                    ? value.predictedEndTranslation.width - value.translation.width
                    : value.translation.width - value.predictedEndTranslation.width
                let flick = velocity > Self.flickPoints
                let settles = reached > 0.5 || (flick && reached > 0.05)

                withAnimation(.spring(duration: 0.3)) {
                    progress = settles ? 1 : 0
                } completion: {
                    guard settles else { return }
                    // The page swap first, then the reset: the other order shows the
                    // outgoing page flat for a frame before it goes.
                    onTurned()
                    progress = 0
                }
                reached = 0
            }
    }

    // MARK: - Constants, shared with the Android shader

    private static let crease = 0.06
    private static let shadow = 0.05
    private static let back = 0.55

    /// How far a finger has to be predicted to travel for the turn to complete anyway.
    ///
    /// `predictedEndTranslation` is SwiftUI's own flick model, so this is a threshold on
    /// its answer rather than a velocity calculation of ours.
    private static let flickPoints: Double = 40
}
