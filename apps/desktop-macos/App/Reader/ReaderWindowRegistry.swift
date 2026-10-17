import AppKit
import SwiftUI

/// The reader windows on screen, by publication, so a second open fronts the first.
///
/// `desktop-experience`, *Opening a publication that is already open*: the window that reads
/// it comes to the front and no second one opens. `openWindow(value:)` was expected to do
/// that on its own for an equal value, and the reader walk measured otherwise on macOS 26:
/// a second call opened a second window. So every open goes through here. A request is
/// remembered for a few seconds, the time a window takes to appear, so two quick clicks on
/// one cover open one window; a request whose window never came does not block the next.
@MainActor
enum ReaderWindowRegistry {
    /// How long an open request stands for a window that has not appeared yet.
    static let requestLifetime: Duration = .seconds(3)

    private final class WeakWindow {
        weak var window: NSWindow?
        init(_ window: NSWindow) { self.window = window }
    }

    private static var windows: [String: WeakWindow] = [:]
    private static var requested: [String: ContinuousClock.Instant] = [:]

    /// Fronts the window reading this publication, or asks for one.
    static func present(_ target: ReaderTarget, open: (ReaderTarget) -> Void) {
        let id = target.publicationID
        if let window = windows[id]?.window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }
        if let asked = requested[id], ContinuousClock.now - asked < requestLifetime { return }
        requested[id] = .now
        open(target)
    }

    static func attach(_ window: NSWindow, for target: ReaderTarget) {
        windows[target.publicationID] = WeakWindow(window)
        requested[target.publicationID] = nil
    }

    static func detach(_ target: ReaderTarget) {
        windows[target.publicationID] = nil
        requested[target.publicationID] = nil
    }

    /// The window reading this publication, if one is on screen.
    static func window(for target: ReaderTarget) -> NSWindow? {
        windows[target.publicationID]?.window
    }
}

extension OpenWindowAction {
    /// Opens a reader for this publication, or fronts the one already reading it.
    @MainActor
    func reader(_ target: ReaderTarget) {
        ReaderWindowRegistry.present(target) { callAsFunction(value: $0) }
    }
}
