public import SwiftUI

public import StoryArcCore

// The fold of a foldable display, as both readers see it: `native-experience`, *Foldable
// devices*, and `foldables-and-iphone-duo`.
//
// iOS 27.1 reports the fold as a `ReservedRegion` of kind `.division`, the camera as one of kind
// `.occlusion`, and the hinge through `onHingeChange`. ``FoldSensor`` turns those into one
// ``DeviceFold`` at the edge, because `ReservedRegion` has no public initializer. A test or a
// snapshot hands a ``DeviceFold`` in through the environment instead.
//
// Here rather than in one reader, because the comic reader and the EPUB reader share this module
// and no other.

extension EnvironmentValues {
    /// A fold handed in by a test or a snapshot, in global coordinates.
    ///
    /// A reader prefers the fold its own device reports. With neither, it draws the flat layout.
    @Entry public var deviceFold: DeviceFold?
}

extension View {
    /// Writes the fold this device reports into `fold`: nothing before iOS 27.1, and nothing on
    /// a display with no reserved region.
    @ViewBuilder
    public func sensingFold(into fold: Binding<DeviceFold?>) -> some View {
        #if os(iOS)
        if #available(iOS 27.1, *) {
            modifier(FoldSensor(fold: fold))
        } else {
            self
        }
        #else
        self
        #endif
    }
}

#if os(iOS)
/// The edge between iOS 27.1's reserved regions and hinge, and a reader's ``DeviceFold``.
///
/// Assumed: a region's `frame` is in the coordinates of the proxy that was asked, as a safe-area
/// inset is. `.fixed` keeps it unmirrored, so it converts to global coordinates by the proxy's
/// own origin. The iPhone Duo simulator needs the iOS 27.1 runtime, so no run has checked this.
@available(iOS 27.1, *)
private struct FoldSensor: ViewModifier {
    @Binding var fold: DeviceFold?
    @State private var regions = DeviceFold(division: nil)
    @State private var isHalfOpen = false

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: DeviceFold.self) { proxy in
                let origin = proxy.frame(in: .global).origin
                func frames(_ kind: ReservedRegion.Kind) -> [CGRect] {
                    proxy.reservedRegions(kind: kind, layoutDirectionBehavior: .fixed)
                        .map { $0.frame.offsetBy(dx: origin.x, dy: origin.y) }
                }
                return DeviceFold(division: frames(.division).first, occlusions: frames(.occlusion))
            } action: { regions = $0 }
            .onHingeChange { _, now in isHalfOpen = now.hinge?.status == .partiallyOpen }
            .onChange(of: reported, initial: true) { _, now in fold = now }
    }

    /// `nil` on a display that reserves nothing, so the flat layout needs no fold at all.
    private var reported: DeviceFold? {
        guard regions.division != nil || !regions.occlusions.isEmpty else { return nil }
        return DeviceFold(division: regions.division, occlusions: regions.occlusions, isHalfOpen: isHalfOpen)
    }
}
#endif
