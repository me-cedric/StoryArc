internal import SwiftUI
internal import UIKit

/// Reader-local screen brightness, across the reader's whole lifecycle.
///
/// `reading-themes`, *Brightness is reader-local*: "the change applies while the reader is
/// open and is reverted on leaving it" and "the system brightness is not permanently
/// modified". Four moments carry that:
///
/// - **Arrival**: the device's own level is captured, so leaving has something to put back.
/// - **A slider move**: applied immediately, so the reader sees what they are choosing.
/// - **A return from the background**: iOS reverts an app's brightness change the moment it
///   leaves the foreground, which Apple documents and which `EpubReaderView` had no handling
///   for at all — a return from the background showed the device's own level again, with the
///   slider still reporting the reader's.
/// - **Departure**: the captured value goes back, but only when the reader set one. With
///   none, nothing reader-local is in force, and restoring the captured value would undo a
///   Control Center change the reader made while reading — a second, quieter bug the first
///   fix would otherwise have papered over.
///
/// The two decisions are plain functions rather than lines inside a closure, because no test
/// in this target can drive a scene-phase transition or a view's `onDisappear`. `EpubReaderBrightnessTests`
/// is what proves them; the extension below is what a preview or a screenshot exercises.
///
/// Split out of `EpubReaderView.swift` at the 400-line cap. Two more `onAppear`/`onDisappear`
/// pairs are how SwiftUI lets a modifier chain attach without folding this into the view's own,
/// which carry the idle timer and the appearance link instead.
enum EpubReaderBrightness {
    /// What `onDisappear` should write back, or `nil` to leave the system alone.
    ///
    /// Only when the reader set a reader-local brightness: with none, nothing this screen put
    /// in force needs undoing, and writing the captured value back would silently discard a
    /// Control Center change the reader made mid-session.
    static func onDeparture(readerBrightness: Double?, captured: CGFloat?) -> CGFloat? {
        guard readerBrightness != nil else { return nil }
        return captured
    }

    /// What a scene-phase change should write, or `nil` to leave the system alone.
    ///
    /// Only on a return to `.active`, and only with a reader-local brightness to reapply —
    /// a reader who never touched the slider has nothing to reassert, and iOS already shows
    /// the device's own level for them.
    static func onScenePhaseChange(to phase: ScenePhase, readerBrightness: Double?) -> CGFloat? {
        guard phase == .active, let readerBrightness else { return nil }
        return CGFloat(readerBrightness)
    }
}

extension View {
    func epubBrightness(
        model: EpubReaderModel,
        scenePhase: ScenePhase,
        captured: Binding<CGFloat?>
    ) -> some View {
        self
            .onAppear { captured.wrappedValue = UIScreen.main.brightness }
            .onDisappear {
                if let restored = EpubReaderBrightness.onDeparture(
                    readerBrightness: model.brightness,
                    captured: captured.wrappedValue
                ) {
                    UIScreen.main.brightness = restored
                }
            }
            .onChange(of: model.brightness) { _, new in
                if let new { UIScreen.main.brightness = CGFloat(new) }
            }
            .onChange(of: scenePhase) { _, phase in
                if let toApply = EpubReaderBrightness.onScenePhaseChange(
                    to: phase,
                    readerBrightness: model.brightness
                ) {
                    UIScreen.main.brightness = toApply
                }
            }
    }
}
