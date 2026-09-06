/// What one page turn cost, counted in frames rather than in seconds.
///
/// `page-transitions`, *Frame budget*, asks that a transition "holds the display's refresh
/// rate, and a dropped frame during a turn is treated as a defect". Nothing in this
/// repository had ever counted a frame, so the scenario had no instrument that could fail.
/// This is that instrument, and it deliberately states no rate.
///
/// **The refresh rate is an input, never a constant here.** ``FrameProbe`` reads it from the
/// display the turn is drawn on and hands it to ``record(at:expecting:)`` as `expecting`.
/// This type therefore says nothing about 60 Hz or 120 Hz, and neither does any test of it.
/// A simulator draws at its Mac's rate and an emulator at its host's, so the only place a
/// number about a reader's phone can be taken is a reader's phone.
///
/// Android's `FrameRun` holds the same arithmetic, rule for rule.
struct FrameRun {

    /// Whether this run may start. ``FrameProbe`` decides it, once per turn.
    let isEnabled: Bool

    private(set) var isRecording = false

    /// Frames the display delivered while the turn ran.
    private(set) var delivered = 0

    /// Frames the display could have delivered in the same time and did not.
    private(set) var dropped = 0

    /// Seconds from the first frame to the last. Zero until a second frame arrives.
    private(set) var span: Double = 0

    private var first: Double?
    private var last: Double?

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    /// Starts counting.
    ///
    /// A disabled run stays stopped. A run that is already counting is left alone, because a
    /// second drag that catches a settling curl continues one turn rather than starting a
    /// second one.
    mutating func begin() {
        guard isEnabled, !isRecording else { return }
        isRecording = true
        delivered = 0
        dropped = 0
        span = 0
        first = nil
        last = nil
    }

    /// Takes one delivered frame.
    ///
    /// `interval` is how long the display said this frame should take. A gap of two intervals
    /// means one frame was not delivered. A gap is rounded to whole frames, so jitter below
    /// half a frame is not reported as a drop.
    ///
    /// Two inputs carry no information and are refused rather than guessed at. An interval of
    /// zero or less means the display reported no rate. A timestamp no later than the one
    /// before it means the clock did not advance. In both cases the frame is counted and
    /// nothing is inferred about drops.
    mutating func record(at timestamp: Double, expecting interval: Double) {
        guard isRecording else { return }
        delivered += 1
        if let first {
            span = max(0, timestamp - first)
        } else {
            first = timestamp
        }
        if let last, interval > 0, timestamp > last {
            let frames = min((timestamp - last) / interval, Self.gapCeiling).rounded()
            dropped += max(0, Int(frames) - 1)
        }
        last = timestamp
    }

    /// Stops counting and keeps what was counted.
    mutating func end() {
        isRecording = false
    }

    /// A gap wider than this many frames is not a dropped frame, it is a suspended app or a
    /// display that reported nonsense. Counting it exactly could overflow `Int`; counting it
    /// as this keeps the report finite and obviously wrong.
    private static let gapCeiling: Double = 1000
}
