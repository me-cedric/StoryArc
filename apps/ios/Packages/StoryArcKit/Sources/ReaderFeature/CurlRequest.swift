internal import StoryArcCore

/// A turn asked of the curl by something that is not a finger: a tap zone, a key, a game
/// controller, or VoiceOver's own page-turn action.
///
/// `page-transitions` gives Curl one motion, and the finger was the only thing that ran
/// it. Every other trigger cut straight to the next page, so the same turn looked like two
/// different modes depending on how it was asked for. A request is what closes that: it is
/// handed to ``CurledPages``, which springs its own progress to a whole turn and then
/// reports it exactly the way a released drag does. Android's `Paging.Curled` is the twin,
/// and runs the same spring from `goTo`.
struct CurlRequest: Equatable {
    /// True for the next page in reading order, false for the page behind.
    let isForward: Bool

    /// Tells two consecutive requests in the same direction apart.
    ///
    /// Without it a second tap on the same edge is an identical value, `onChange` sees no
    /// change, and the reader turns one page for two taps.
    let serial: Int
}

extension CurlRequest {

    /// Whether a discrete turn of `step` display positions runs the curl rather than
    /// cutting to the page.
    ///
    /// Only in Curl mode, because every other mode brings its own motion. Only one
    /// position at a time, because a jump across a publication has no fold to roll — the
    /// slider and the thumbnail strip go on cutting. And only where the destination
    /// exists, so a refused turn still reaches its haptic and its rubber-band (D13)
    /// instead of curling into nothing.
    static func runsCurl(mode: PageTransition, step: Int, hasDestination: Bool) -> Bool {
        mode == .pageCurl && abs(step) == 1 && hasDestination
    }
}
