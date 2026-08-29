#if os(iOS)
public import UIKit

/// Which way up the app is willing to be, while a reader is holding it there.
///
/// `comic-reader`: a locked orientation "stays locked for the reader only, and the rest
/// of the app follows the device". UIKit has no per-screen answer to that question — it
/// asks the application delegate once, through
/// `application(_:supportedInterfaceOrientationsFor:)`, and a SwiftUI `App` with no
/// delegate reports whatever `Info.plist` lists for every screen there is. So the reader
/// writes what it wants here and the app target's delegate reads it back; the reader is
/// also what puts it back, on the way out.
///
/// Static rather than owned by the reader, because the delegate is handed no reader to
/// ask and there is one window with one reader in it.
///
/// A geometry request alone would rotate the screen once and then let the device rotate
/// it back, because such a request is resolved against exactly this mask. Narrowing the
/// mask is the part that holds.
@MainActor
public enum ReaderOrientation {
    /// Everything the delegate will allow. Intersected with `Info.plist`, so `.all` means
    /// the orientations the app already declares rather than four the phone would refuse.
    public private(set) static var allowed: UIInterfaceOrientationMask = .all

    /// Holds the app at the way up it is showing now.
    static func hold() {
        allowed = mask(for: scene?.interfaceOrientation)
        reconsider()
    }

    /// Gives the orientation back to the device.
    static func release() {
        allowed = .all
        reconsider()
    }

    /// Asks UIKit to put the question again, now that the answer has changed.
    ///
    /// To the topmost presented controller rather than to the root: the reader is a
    /// full-screen cover, so the root is underneath it and is not the one UIKit consults.
    private static func reconsider() {
        var controller = scene?.keyWindow?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        controller?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }

    /// The one orientation, as the mask that permits only it.
    ///
    /// `.all` for an orientation UIKit could not report, which leaves the device in
    /// charge — a lock that cannot say what it is locking to should do nothing rather
    /// than guess portrait.
    private static func mask(for orientation: UIInterfaceOrientation?) -> UIInterfaceOrientationMask {
        switch orientation {
        case .portrait: .portrait
        case .portraitUpsideDown: .portraitUpsideDown
        case .landscapeLeft: .landscapeLeft
        case .landscapeRight: .landscapeRight
        default: .all
        }
    }

    private static var scene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }
}
#endif
