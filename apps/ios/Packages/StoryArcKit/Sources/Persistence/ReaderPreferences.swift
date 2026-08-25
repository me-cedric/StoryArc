public import Foundation

public import StoryArcCore

/// How the reader was left, remembered across launches.
///
/// `comic-reader`: the fit choice "persists per series". Per series is not yet
/// possible — a series is a name inferred from a folder, not an entity anything can
/// be keyed on — so this is one setting for the reader. That is a smaller promise
/// than the spec makes, and it is the honest one until series exist.
///
/// Separate from `LibraryPreferences` because it answers a different question.
/// Android's `ReaderPreferences` keeps the same value in `SharedPreferences`.
///
/// Not `Sendable`: `UserDefaults` is not, and claiming otherwise would be a lie the
/// compiler cannot catch.
public struct ReaderPreferences {
    private let defaults: UserDefaults
    private let fitKey = "app.storyarc.pageFit"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The stored fit, or fit-to-screen — the only mode that never hides a panel.
    public func pageFit() -> PageFit {
        PageFit(rawValue: defaults.string(forKey: fitKey) ?? "") ?? .screen
    }

    public func save(_ fit: PageFit) {
        defaults.set(fit.rawValue, forKey: fitKey)
    }
}
