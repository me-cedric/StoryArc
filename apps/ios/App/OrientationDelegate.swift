#if canImport(CarPlay)
import CarPlay
#endif
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

    /// Gives the scene a delegate of our own, for the callbacks SwiftUI does not surface: a
    /// home-screen quick action, and a car screen. See ``QuickActionSceneDelegate`` and
    /// ``CarSceneDelegate``.
    ///
    /// The configuration is otherwise the system's own, so SwiftUI still builds the phone's
    /// scene and owns everything in it.
    ///
    /// **A car scene reaches here and never connects.** `com.apple.developer.carplay-audio`
    /// and a scene manifest entry are what let the system open one, and ADR-0011's missing
    /// Apple development team blocks the entitlement. The branch is written now so the day
    /// the grant arrives is a plist change rather than a search for where this belongs.
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        #if canImport(CarPlay)
        configuration.delegateClass = connectingSceneSession.role == .carTemplateApplication
            ? CarSceneDelegate.self
            : QuickActionSceneDelegate.self
        #else
        configuration.delegateClass = QuickActionSceneDelegate.self
        #endif
        return configuration
    }
}
