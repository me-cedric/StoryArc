public import Foundation

/// How fast a listener likes a book read to them.
///
/// `audio-playback`: the speed "is remembered for that publication and offered as the default
/// for others in the same series". Two scopes, resolved in that order, and a bare default
/// under both.
///
/// **Why the series is written as well as the publication.** A listener who settles on 1.4×
/// for volume one has said something about the narrator, not about that file — and volume two
/// arriving at 1× would make them say it again for every book in the series. So a choice
/// writes both entries, and the publication's own always wins: adjusting volume two does not
/// reach back and change volume one.
///
/// Keys rather than one serialised blob, unlike ``ReaderPreferences/themes()``: there is no
/// walk to reimplement here — two lookups and a default — and a key per publication is what
/// lets a library of five hundred books not rewrite a single document on every change.
///
/// A `Double` rather than a `PlaybackSpeed`, because `Persistence` does not depend on
/// `Playback` and should not: this is a store, and clamping a rate to the offered range is the
/// player's rule. `PlaybackSpeed(_:)` is where a rate from anywhere lands somewhere valid.
/// Android's `PlaybackPreferences` returns a bare `Double` for the same reason.
///
/// Not `Sendable`: `UserDefaults` is not, and claiming otherwise would be a lie the compiler
/// cannot catch. It is cheap to construct where it is needed.
public struct PlaybackPreferences {
    private let defaults: UserDefaults
    private let prefix = "app.storyarc.playbackSpeed"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Neither slower nor faster than the narrator recorded it.
    public static let normalRate = 1.0

    /// The speed to start this publication at.
    ///
    /// - Parameters:
    ///   - publicationID: the publication's stable id.
    ///   - series: what it belongs to, or `nil` for a publication that belongs to nothing.
    ///
    /// **A stored zero is not a remembered speed.** `UserDefaults` answers `0` for a key it has
    /// never seen, so the number is only believed where it is above zero — otherwise every
    /// untouched book would start stopped, which is the one value a speed may never be.
    public func speed(of publicationID: String, series: String?) -> Double {
        let own = defaults.double(forKey: key(publication: publicationID))
        if own > 0 { return own }
        let shared = series.map { defaults.double(forKey: key(series: $0)) } ?? 0
        return shared > 0 ? shared : Self.normalRate
    }

    /// Remembers a speed for this publication, and offers it to the rest of the series.
    public func remember(_ rate: Double, of publicationID: String, series: String?) {
        defaults.set(rate, forKey: key(publication: publicationID))
        if let series { defaults.set(rate, forKey: key(series: series)) }
    }

    /// Forgets every remembered speed.
    ///
    /// `settings-and-about` requires what the app remembers about reading to be clearable, and
    /// a speed is one of those things. Deliberately every entry: a listener clearing their
    /// history does not mean "all but the series defaults".
    public func clear() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }

    private func key(publication id: String) -> String { "\(prefix).publication.\(id)" }

    private func key(series: String) -> String { "\(prefix).series.\(series)" }
}
