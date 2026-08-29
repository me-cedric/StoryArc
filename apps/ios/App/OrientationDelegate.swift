import ReaderFeature
import UIKit

/// The one place UIKit asks which way up this app may be.
///
/// `comic-reader` locks the *reader's* orientation and leaves the rest of the app
/// following the device. UIKit has no per-screen version of that question: it asks the
/// application delegate, once, for the whole app — and a SwiftUI `App` that supplies no
/// delegate answers with `Info.plist` and nothing else. So the reader states what it
/// wants in `ReaderOrientation` and this reads it back.
///
/// The narrowest delegate that can carry the requirement. Nothing else about the app's
/// lifecycle is handled here; SwiftUI keeps all of it.
final class OrientationDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        ReaderOrientation.allowed
    }
}
