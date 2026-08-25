internal import Foundation
#if canImport(UIKit)
internal import UIKit
#endif

/// What the About screen can say about this build.
///
/// Read from the bundle rather than hard-coded, because a hard-coded version in an About
/// screen is a version that is wrong by the next release.
enum BuildInfo {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    // Literal URLs. `URL(string:)` is non-failing for these because they are written
    // here once and read five times; an optional would be plumbing for nothing.
    static let repository = URL(string: "https://github.com/me-cedric/StoryArc")!
    static let author = URL(string: "https://github.com/me-cedric")!
    static let licence = URL(string: "https://github.com/me-cedric/StoryArc/blob/main/LICENSE")!
    static let support = URL(string: "https://ko-fi.com/mecedric")!

    /// The issue tracker, pre-filled with what a bug report needs and nothing else.
    ///
    /// `settings-and-about`: "the app version, platform version, and device class
    /// pre-filled, and no personal data". Device *class* rather than device — the model
    /// identifier is not personal on its own, but it narrows a person far more than
    /// "iPhone" does, and the spec asked for the class.
    static var issue: URL {
        var components = URLComponents(string: "https://github.com/me-cedric/StoryArc/issues/new")
        #if canImport(UIKit)
        let platform = "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        let deviceClass = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #else
        let platform = "macOS"
        let deviceClass = "Mac"
        #endif
        components?.queryItems = [
            URLQueryItem(
                name: "body",
                value: "StoryArc \(version) (\(build))\n\(platform)\n\(deviceClass)\n\n"
            )
        ]
        return components?.url ?? repository
    }
}
