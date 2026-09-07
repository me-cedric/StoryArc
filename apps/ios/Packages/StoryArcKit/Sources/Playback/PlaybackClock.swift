public import Foundation

internal import StoryArcCore

/// How long something runs, in the two forms a listener needs.
///
/// **Here rather than beside one surface, because two surfaces state the same lengths.** The
/// player writes a position and the publication page writes a chapter's length, and both owe
/// a screen reader the spoken form of it. The arithmetic lived in `PlayerLabels` and again,
/// byte for byte, in `DetailChapters` — two copies that could disagree about what `1:02:30`
/// means, in a module neither surface could reach. `Playback` is the module both reach:
/// `PlayerFeature` draws it and `LibraryFeature` depends on it for ``PlaybackPart``.
public enum PlaybackClock {

    /// A length as a player writes it: `9:59`, or `1:02:30` past the hour.
    ///
    /// Built by hand rather than by a formatter, because this one is not prose: it is the
    /// digits every media player in the world shows, and a locale that reordered them would
    /// be one where a listener could not read their own book's clock.
    public static func time(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let whole = Int(seconds.rounded(.down))
        let hours = whole / 3600
        let minutes = (whole % 3600) / 60
        let secs = whole % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// The same length as a screen reader should hear it: "1 minute, 10 seconds".
    ///
    /// `9:59` is right on the face of a control and wrong in a screen reader, which reads it
    /// "nine colon fifty nine".
    public static func spokenTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return words(.seconds(0)) }
        return words(.seconds(seconds.rounded()))
    }

    /// A duration in the platform's own units, in the interface language.
    ///
    /// `Duration`'s own units format, so the words and their order are the platform's in
    /// every language rather than four more strings this project would have to keep in step.
    ///
    /// The platform speaks the locale it is handed, and it is handed
    /// ``StoryArcCore/Locale/storyArc``. A formatter left on the process locale said
    /// "1 minute, 10 seconds" to a screen reader inside a French interface.
    public static func words(_ duration: Duration) -> String {
        duration.formatted(
            .units(allowed: [.hours, .minutes, .seconds], width: .wide).locale(.storyArc)
        )
    }
}
