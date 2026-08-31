internal import SwiftUI

#if os(iOS)
internal import UIKit
#endif

/// What the reader asks of the *system's* chrome while a page is on screen.
///
/// Three rules, all `comic-reader`'s, and none of them about a control this app draws:
///
/// - the status and home indicators dim with the reader's own chrome;
/// - "the screen does not auto-lock while a page is visible, and normal locking resumes on
///   leaving" — a long look at one page is reading, not idling;
/// - the orientation lock is scoped to the reader, so however the reader left — the close
///   button, the end screen, a swipe — the rest of the app follows the device again.
///
/// Split out of `ReaderView` so that file stays the screen's structure rather than the
/// structure plus its dealings with the platform. It is a modifier rather than an extension
/// because the whole block is `#if os(iOS)`: the package builds for macOS too, so the
/// pure-Swift targets can be tested on the host without a simulator, and one guard around
/// one type reads better than four around four modifiers.
struct ReaderSystemChrome: ViewModifier {
    /// Whether the reader's own controls are on screen. The system's follow them.
    let isChromeVisible: Bool
    /// Whether the reader is holding the device at one way up.
    let isOrientationLocked: Bool

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .statusBarHidden(!isChromeVisible)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
                ReaderOrientation.release()
            }
            .onChange(of: isOrientationLocked) { _, isLocked in
                if isLocked { ReaderOrientation.hold() } else { ReaderOrientation.release() }
            }
        #else
        content
        #endif
    }
}
