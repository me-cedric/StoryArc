internal import Foundation
#if canImport(UIKit)
internal import QuartzCore
#endif

/// The switch that arms ``FrameRun``, and the frame clock that feeds it.
///
/// **It is off unless the app was launched with `-StoryArcFrameProbe YES`.** That argument
/// reaches `UserDefaults` through the argument domain, which nothing but a launch writes and
/// nothing persists. An app opened from the Home screen cannot be armed, so a shipping build
/// pays one `Bool` for this whole file: ``isArmed`` is false, ``ticker`` is never created,
/// no display link is scheduled and no frame is counted.
///
/// `CADisplayLink` is the platform's own frame clock, so what is counted is the display's
/// cadence rather than this code's idea of time, which is the mistake `page-transitions` asks
/// the instrument to avoid: wall-clock seconds are not frames.
///
/// **Android's `FrameProbe` is the twin, and differs in three ways the platform forces.** Its
/// switch is read on every turn rather than once, because a `Settings.Global` key can be
/// changed over the cable while the app runs and a launch argument cannot. Its report goes to
/// `logcat` rather than to standard output, because that is what `adb` reads. And its ticker
/// is held by the composition rather than reached statically, because it needs a `Context`
/// and a `View` to find the switch and the refresh rate, neither of which this needs.
@MainActor
enum FrameProbe {

    /// The launch argument that arms the instrument, without its leading dash.
    static let armingKey = "StoryArcFrameProbe"

    /// Read once: the argument domain cannot change while the process lives.
    static let isArmed = UserDefaults.standard.bool(forKey: armingKey)

    /// One line on standard output, which `scripts/measure-turn.mjs` reads through
    /// `devicectl … --console`. The same wording as Android's, so one regular expression
    /// reads both.
    static func report(_ run: FrameRun) {
        print(
            "StoryArcFrames delivered=\(run.delivered) dropped=\(run.dropped)"
                + " span_ms=\(Int((run.span * 1000).rounded()))"
        )
    }

    /// A page turn started. Called from the drag, never from a view's body.
    static func began() {
        guard isArmed else { return }
        ticker.began()
    }

    /// The page turn finished, whether it settled or sprang back.
    static func ended() {
        guard isArmed else { return }
        ticker.ended()
    }

    /// How long a run opened by a change of displayed index stays open.
    ///
    /// A bound rather than a measurement, and deliberately generous. SwiftUI does not
    /// publish how long the animation behind a `TabView` selection runs, and the
    /// cross-dissolve runs for `ReaderView.fadeDuration`. A window longer than the
    /// animation adds frames drawn while nothing moves, and such a frame still arrives on
    /// the panel's own interval, so it raises the delivered count and not the dropped one.
    /// A window shorter than the animation hides the end of the turn, which is where a
    /// frame is most likely to arrive late.
    ///
    /// Android's `TURN_WINDOW_MILLIS` holds the same number for the same reason.
    ///
    /// `nonisolated` because it is a number rather than a measurement in progress, and
    /// `PageTransition.turnWindow` reads it outside the main actor.
    nonisolated static let turnWindow = 0.5

    /// A turn no gesture bounds: the displayed index moved, the container animates, and
    /// nothing reports the end. Opens a run, and closes it after `window` seconds.
    ///
    /// The curl does not use this. A finger bounds a curl better than any window can, so
    /// `CurledPages` calls `began()` and `ended()` itself.
    static func turned(over window: Double) {
        guard isArmed else { return }
        ticker.began()
        Task {
            try? await Task.sleep(for: .seconds(window))
            ticker.ended()
        }
    }

    /// The view carrying the turn went away before the turn ended. Stops, and reports
    /// nothing. Android's `FrameTicker.cancel` is the twin, called from `onDispose`.
    static func cancel() {
        guard isArmed else { return }
        ticker.cancel()
    }

    private static let ticker = FrameTicker()
}

/// One `CADisplayLink` and the run it feeds.
///
/// `NSObject` because `CADisplayLink` takes a target and a selector and offers no closure.
@MainActor
private final class FrameTicker: NSObject {

    private var run = FrameRun(isEnabled: false)

    #if canImport(UIKit)
    private var link: CADisplayLink?
    #endif

    func began() {
        guard !run.isRecording else { return }
        run = FrameRun(isEnabled: FrameProbe.isArmed)
        run.begin()
        guard run.isRecording else { return }
        #if canImport(UIKit)
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        // `.common`, so the count survives a scroll or a gesture that runs the tracking mode.
        link.add(to: .main, forMode: .common)
        self.link = link
        #endif
    }

    func ended() {
        guard run.isRecording else { return }
        cancel()
        FrameProbe.report(run)
    }

    /// The turn was abandoned: stop counting, and report nothing.
    ///
    /// A run that never reaches ``ended()`` leaves a `CADisplayLink` on the main run loop for
    /// the life of the process, and this ticker is a singleton, so the *next* turn would then
    /// report a span covering the abandoned drag and every idle second after it. Nothing is
    /// reported, because a turn whose end nobody saw has no number worth printing.
    func cancel() {
        guard run.isRecording else { return }
        run.end()
        #if canImport(UIKit)
        link?.invalidate()
        link = nil
        #endif
    }

    #if canImport(UIKit)
    /// `targetTimestamp - timestamp` is the display's own answer for how long this frame has,
    /// so a ProMotion panel reports its interval and a 60 Hz panel reports its own. Nothing
    /// here assumes either.
    ///
    /// Android reads the same interval off the view's display on every frame, because
    /// `Choreographer` reports no interval of its own. Reading it once is wrong on both:
    /// a panel changes its refresh rate while the app runs.
    @objc private func tick(_ link: CADisplayLink) {
        run.record(at: link.timestamp, expecting: link.targetTimestamp - link.timestamp)
    }
    #endif
}
