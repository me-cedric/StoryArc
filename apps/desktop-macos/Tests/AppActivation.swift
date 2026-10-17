import AppKit
import Foundation
import Testing

@testable import StoryArc

/// Brings the test host to the front before a screen is drawn or held against a reference.
///
/// macOS grants activation cooperatively: when another application is in use, the request a
/// double-click in the Finder would make can be refused, and then every window of the host draws
/// inactive, with grey traffic lights, a grey title and the reader's chrome hidden. The snapshot
/// references are drawn active, so a run that cannot come to the front is skipped with that
/// reason instead of failing on every screen. On CI nothing else is in use, so a refusal there
/// is a fault the test must report.
enum AppActivation {
    @MainActor
    static func activate() async -> Bool {
        if NSApplication.shared.isActive { return true }
        _ = try? await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: .init())
        NSApplication.shared.activate()
        return await Walk.until(.seconds(3)) { NSApplication.shared.isActive ? true : nil } != nil
    }

    /// True on CI, where the host can always come to the front and a skip would hide a fault.
    static var isRequired: Bool { ProcessInfo.processInfo.environment["CI"] != nil }

    /// The screens a run could not hold because the app was not in front when they were drawn:
    /// activation can be taken away mid-run by the application in use, one screen at a time.
    @MainActor static var notHeld: [String] = []

    /// Whether `name` can be held now: the app is in front, or came to the front when asked.
    /// When it cannot, the screen is listed in `notHeld` and skipped, or on CI recorded as a fault.
    @MainActor
    static func holdsFront(for name: String, sourceLocation: SourceLocation) async -> Bool {
        if await activate() { return true }
        if isRequired {
            Issue.record("\(name): the app is not in front, so the window draws inactive",
                         sourceLocation: sourceLocation)
        } else {
            notHeld.append(name)
        }
        return false
    }

    static let refusal = "the app could not come to the front, so every window would draw inactive; " +
        "run the test with no other application in use"
}
