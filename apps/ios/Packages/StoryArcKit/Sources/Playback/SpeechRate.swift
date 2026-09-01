public import Foundation

internal import AVFoundation

/// The player's speed, in the units a synthesised utterance takes.
///
/// **Why this exists at all.** Readium 3.11.0's `PublicationSpeechSynthesizer.Configuration`
/// carries a language and a voice and no rate, and `AVTTSEngine.swift:131` — the line that
/// would apply one — is commented out upstream. That is not an oversight: two lines below
/// it, the same method calls `delegate?.avTTSEngine(self, didCreateUtterance:)`, whose own
/// doc comment reads *"You can customize additional properties of the utterance."* Upstream
/// is saying the caller sets this now. So the app supplies the delegate, and the delegate
/// needs a number — which Readium's own `rateMultiplierToAVRate` would have given it, except
/// that it is `private` and, at this version, deleted along with the line that called it.
///
/// **Two lines, not one, and the join is the point.** `AVSpeechUtterance.rate` runs from
/// `AVSpeechUtteranceMinimumSpeechRate` to `AVSpeechUtteranceMaximumSpeechRate` with
/// `AVSpeechUtteranceDefaultSpeechRate` in between — measured on 2026-09-01 as `0.0`, `1.0`
/// and `0.5`, which are evenly spaced *as numbers*. That is the trap: a single lerp from the
/// player's 0.5×–3× onto that range looks correct and puts 1× at `0.2`, a fifth of the way
/// up, when the platform's own idea of ordinary speech is `0.5`. A reader who never touched
/// the control would hear a voice slower than every other spoken thing on the device.
///
/// So the player's normal speed is pinned to the platform's normal rate, and each half of
/// the range is interpolated to its own end. `SpeechRateTests` asserts all three anchors,
/// and asserts explicitly that 1× is *not* where the naive line would put it.
///
/// **Only the synthesised source uses this.** A narrated file changes speed with
/// `AVPlayer.rate`, which is already a multiplier — see `NarratedSource`. Two engines, two
/// unit systems, one ``PlaybackSpeed`` in front of both, which is the whole point of having
/// the type.
public enum SpeechRate {

    /// The utterance rate for a playback speed.
    ///
    /// The result is always inside the platform's range: ``PlaybackSpeed`` clamps its own
    /// input, so there is no speed that could ask for a rate `AVSpeechUtterance` would pin
    /// silently — and a pinned rate is a voice speaking at a speed the player is stating
    /// wrongly.
    public static func avRate(for speed: PlaybackSpeed) -> Float {
        let slowest = Double(AVSpeechUtteranceMinimumSpeechRate)
        let ordinary = Double(AVSpeechUtteranceDefaultSpeechRate)
        let fastest = Double(AVSpeechUtteranceMaximumSpeechRate)

        if speed.rate <= PlaybackSpeed.normal.rate {
            return Float(
                interpolate(
                    speed.rate,
                    from: PlaybackSpeed.slowestRate...PlaybackSpeed.normal.rate,
                    onto: slowest...ordinary
                )
            )
        }
        return Float(
            interpolate(
                speed.rate,
                from: PlaybackSpeed.normal.rate...PlaybackSpeed.fastestRate,
                onto: ordinary...fastest
            )
        )
    }

    private static func interpolate(
        _ value: Double,
        from source: ClosedRange<Double>,
        onto target: ClosedRange<Double>
    ) -> Double {
        let span = source.upperBound - source.lowerBound
        guard span > 0 else { return target.lowerBound }
        let fraction = min(1, max(0, (value - source.lowerBound) / span))
        return target.lowerBound + fraction * (target.upperBound - target.lowerBound)
    }
}
