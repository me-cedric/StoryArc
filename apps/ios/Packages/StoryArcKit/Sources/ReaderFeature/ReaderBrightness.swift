internal import SwiftUI

#if os(iOS)
internal import UIKit
#endif

/// Reader-local screen brightness, across the comic reader's whole lifecycle.
///
/// `reading-themes`, *Brightness is reader-local*: "the change applies while the reader is
/// open and is reverted on leaving it" and "the system brightness is not permanently
/// modified". Four moments carry that, word for word what `EpubReaderBrightness` already
/// proved for the reflowable reader:
///
/// - **Arrival**: the device's own level is captured, so leaving has something to put back.
/// - **A slider move**: applied immediately, so the reader sees what they are choosing.
/// - **A return from the background**: iOS reverts an app's brightness change the moment it
///   leaves the foreground, which a return from the background would otherwise show as the
///   device's own level while the slider kept reporting the reader's.
/// - **Departure**: the captured value goes back, but only when the reader set one.
///
/// The two decisions below are plain functions, UIKit-free, so `ReaderBrightnessTests`
/// proves them on the host. `#if os(iOS)` guards only the `UIScreen` reads and writes that
/// act on them — ``ReaderSystemChrome`` is why that split exists in this package: it builds
/// for macOS too, so the pure-Swift targets can be tested without a simulator.
///
/// A mirror of `EpubReaderBrightness` rather than a shared call: the two targets have no
/// dependency between them, and the four lines this exists for are cheaper duplicated than
/// a new cross-package import would be to justify.
enum ReaderBrightness {
    /// The device's own brightness, read fresh. 1 on a platform with no such concept — only
    /// the host's macOS test build ever sees that branch, never the app.
    static var deviceBrightness: Double {
        #if os(iOS)
        Double(UIScreen.main.brightness)
        #else
        1
        #endif
    }

    /// What `onDisappear` should write back, or `nil` to leave the system alone.
    static func onDeparture(readerBrightness: Double?, captured: Double?) -> Double? {
        guard readerBrightness != nil else { return nil }
        return captured
    }

    /// What a scene-phase change should write, or `nil` to leave the system alone.
    static func onScenePhaseChange(to phase: ScenePhase, readerBrightness: Double?) -> Double? {
        guard phase == .active, let readerBrightness else { return nil }
        return readerBrightness
    }
}

extension View {
    func readerBrightness(
        model: ReaderModel,
        scenePhase: ScenePhase,
        captured: Binding<Double?>
    ) -> some View {
        #if os(iOS)
        self
            .onAppear { captured.wrappedValue = ReaderBrightness.deviceBrightness }
            .onDisappear {
                if let restored = ReaderBrightness.onDeparture(
                    readerBrightness: model.brightness,
                    captured: captured.wrappedValue
                ) {
                    UIScreen.main.brightness = CGFloat(restored)
                }
            }
            .onChange(of: model.brightness) { _, new in
                if let new { UIScreen.main.brightness = CGFloat(new) }
            }
            .onChange(of: scenePhase) { _, phase in
                if let toApply = ReaderBrightness.onScenePhaseChange(
                    to: phase,
                    readerBrightness: model.brightness
                ) {
                    UIScreen.main.brightness = CGFloat(toApply)
                }
            }
        #else
        self
        #endif
    }
}
