import AppKit
import SwiftUI

/// Reaches the `NSWindow` a SwiftUI view is in, for the things SwiftUI has no modifier for:
/// the window's frame for restoration, full screen, and whether it is key.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window { onWindow(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window { onWindow(window) }
    }
}

/// What a reader window watches on its `NSWindow`: key status, moves and resizes.
@MainActor
final class ReaderWindowObserver {
    private(set) weak var window: NSWindow?
    private var observers: [any NSObjectProtocol] = []
    private let onKey: @MainActor (Bool) -> Void
    private let onFrame: @MainActor (CGRect) -> Void

    init(onKey: @escaping @MainActor (Bool) -> Void, onFrame: @escaping @MainActor (CGRect) -> Void) {
        self.onKey = onKey
        self.onFrame = onFrame
    }

    func attach(_ window: NSWindow) {
        guard self.window !== window else { return }
        detach()
        self.window = window
        let center = NotificationCenter.default
        let key = onKey
        let frame = onFrame
        observers = [
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { _ in
                MainActor.assumeIsolated { key(true) }
            },
            center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { _ in
                MainActor.assumeIsolated { key(false) }
            },
            center.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak window] _ in
                MainActor.assumeIsolated { if let window { frame(window.frame) } }
            },
            center.addObserver(
                forName: NSWindow.didEndLiveResizeNotification, object: window, queue: .main
            ) { [weak window] _ in
                MainActor.assumeIsolated { if let window { frame(window.frame) } }
            },
        ]
        if window.isKeyWindow { key(true) }
    }

    func detach() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        window = nil
    }

    isolated deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
}
