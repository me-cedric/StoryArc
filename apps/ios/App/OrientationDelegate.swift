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
/// The narrowest delegate that can carry the requirement, and the one place a scene
/// delegate can be installed. Nothing else about the app's lifecycle is handled here;
/// SwiftUI keeps all of it.
final class OrientationDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        ReaderOrientation.allowed
    }

    /// Gives the scene a delegate of our own, for the one callback SwiftUI does not
    /// surface: a home-screen quick action. See ``QuickActionSceneDelegate``.
    ///
    /// The configuration is otherwise the system's own, so SwiftUI still builds the scene
    /// and owns everything in it.
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = QuickActionSceneDelegate.self
        return configuration
    }
}
