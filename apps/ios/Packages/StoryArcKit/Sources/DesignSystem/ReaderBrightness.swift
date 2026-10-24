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

    /// The store over the key window's screen, asked again at each moment because the reader
    /// can move to the other display of an iPhone Duo while it is open.
    @MainActor
    static var store: BrightnessStore {
        #if os(iOS)
        BrightnessStore(screen: screen)
        #else
        BrightnessStore(screen: nil)
        #endif
    }

    /// The device's own level, or full brightness where no window is up.
    @MainActor
    public static var deviceBrightness: Double { store.level }

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

/// A display whose brightness the reader sets: the scene's `UIScreen`, or a test's own.
@MainActor
protocol BrightnessScreen: AnyObject {
    var level: Double { get set }
}

#if os(iOS)
extension UIScreen: BrightnessScreen {
    var level: Double {
        get { Double(brightness) }
        set { brightness = CGFloat(newValue) }
    }
}
#endif

/// The four moments of ``ReaderBrightness``, each read or written through one screen.
///
/// `BrightnessStoreTests` hands in a screen of its own, so the reads and the writes are
/// asserted on the host, with no device and no `UIScreen.main`.
@MainActor
struct BrightnessStore {
    let screen: (any BrightnessScreen)?

    /// The screen's level, or full brightness where there is no screen.
    var level: Double { screen?.level ?? 1 }

    /// A slider move, applied at once.
    func apply(_ readerBrightness: Double?) {
        if let readerBrightness { screen?.level = readerBrightness }
    }

    /// Leaving the reader. See ``ReaderBrightness/onDeparture(readerBrightness:captured:)``.
    func depart(readerBrightness: Double?, captured: Double?) {
        apply(ReaderBrightness.onDeparture(readerBrightness: readerBrightness, captured: captured))
    }

    /// A scene-phase change. See ``ReaderBrightness/onScenePhaseChange(to:readerBrightness:)``.
    func sceneChanged(to phase: ScenePhase, readerBrightness: Double?) {
        apply(ReaderBrightness.onScenePhaseChange(to: phase, readerBrightness: readerBrightness))
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
            .onAppear { captured.wrappedValue = ReaderBrightness.store.level }
            .onDisappear {
                ReaderBrightness.store.depart(
                    readerBrightness: brightness.wrappedValue,
                    captured: captured.wrappedValue
                )
            }
            .onChange(of: brightness.wrappedValue) { _, new in ReaderBrightness.store.apply(new) }
            .onChange(of: scenePhase) { _, phase in
                ReaderBrightness.store.sceneChanged(to: phase, readerBrightness: brightness.wrappedValue)
            }
        #else
        self
        #endif
    }
}
