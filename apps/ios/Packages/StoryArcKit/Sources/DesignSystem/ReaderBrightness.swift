public import SwiftUI

#if os(iOS)
internal import UIKit
#endif

/// Reader-local screen brightness, across a reader's whole lifecycle.
///
/// `reading-themes`, *Brightness is reader-local*: "the change applies while the reader is
/// open and is reverted on leaving it" and "the system brightness is not permanently
/// modified". Four moments carry that:
///
/// - **Arrival**: the device's own level is captured, so leaving has something to put back.
/// - **A slider move**: applied immediately, so the reader sees what they are choosing.
/// - **A return from the background**: iOS reverts an app's brightness change the moment it
///   leaves the foreground, which Apple documents. Without this, a return from the background
///   shows the device's own level again, with the slider still reporting the reader's.
/// - **Departure**: the captured value goes back, but only when the reader set one. With
///   none, nothing reader-local is in force, and restoring the captured value would undo a
///   Control Center change the reader made while reading.
///
/// One modifier for both readers. The comic reader and the EPUB reader each carried a copy,
/// because the comment on the comic one said the two targets share no dependency; they share
/// this one. The two decisions are plain functions rather than lines inside a closure, because
/// no host test can drive a scene-phase transition or a view's `onDisappear`.
/// `ReaderBrightnessTests` is what proves them.
public enum ReaderBrightness {
    #if os(iOS)
    /// The screen the app's key window is on.
    ///
    /// `UIScreen.main` is deprecated, and on an iPhone Duo it names one display whichever
    /// one the reader is on. The window's scene names the display in use (D6 of
    /// `foldables-and-iphone-duo`).
    @MainActor
    static var screen: UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.windowScene?.screen
    }
    #endif

    /// The device's own level, or full brightness where no window is up.
    @MainActor
    public static var deviceBrightness: Double {
        #if os(iOS)
        Double(screen?.brightness ?? 1)
        #else
        1
        #endif
    }

    /// What `onDisappear` should write back, or `nil` to leave the system alone.
    ///
    /// Only when the reader set a reader-local brightness: with none, nothing this screen put
    /// in force needs undoing, and writing the captured value back would silently discard a
    /// Control Center change the reader made mid-session.
    static func onDeparture(readerBrightness: Double?, captured: Double?) -> Double? {
        guard readerBrightness != nil else { return nil }
        return captured
    }

    /// What a scene-phase change should write, or `nil` to leave the system alone.
    ///
    /// Only on a return to `.active`, and only with a reader-local brightness to reapply. A
    /// reader who never touched the slider has nothing to reassert, and iOS already shows
    /// the device's own level for them.
    static func onScenePhaseChange(to phase: ScenePhase, readerBrightness: Double?) -> Double? {
        guard phase == .active, let readerBrightness else { return nil }
        return readerBrightness
    }
}

extension View {
    /// Applies `brightness` to the screen while this view is up, and puts `captured` back
    /// on leaving. `captured` is written on arrival; the caller only holds it.
    public func readerBrightness(
        _ brightness: Binding<Double?>,
        scenePhase: ScenePhase,
        captured: Binding<Double?>
    ) -> some View {
        #if os(iOS)
        self
            .onAppear { captured.wrappedValue = ReaderBrightness.deviceBrightness }
            .onDisappear {
                if let restored = ReaderBrightness.onDeparture(
                    readerBrightness: brightness.wrappedValue,
                    captured: captured.wrappedValue
                ) {
                    ReaderBrightness.screen?.brightness = CGFloat(restored)
                }
            }
            .onChange(of: brightness.wrappedValue) { _, new in
                if let new { ReaderBrightness.screen?.brightness = CGFloat(new) }
            }
            .onChange(of: scenePhase) { _, phase in
                if let toApply = ReaderBrightness.onScenePhaseChange(
                    to: phase,
                    readerBrightness: brightness.wrappedValue
                ) {
                    ReaderBrightness.screen?.brightness = CGFloat(toApply)
                }
            }
        #else
        self
        #endif
    }
}
