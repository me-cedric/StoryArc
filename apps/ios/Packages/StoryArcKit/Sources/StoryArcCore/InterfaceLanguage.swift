public import Foundation

internal import Synchronization

/// The language the interface speaks.
///
/// `localization` requires the app to follow the device and to allow an override that
/// "switches immediately without a restart". iOS fixes `Bundle.main`'s language at launch,
/// so the override cannot come from the bundle; it comes from the locale every lookup is
/// given. SwiftUI resolves a `Text` against the environment's locale, and a `String(localized:)`
/// against the one it is handed — ``Locale/storyArc`` is that one.
public enum InterfaceLanguage {
    /// The tags StoryArc ships, in the order a reader sees them.
    public static let supported = ["en", "de", "es", "fr"]

    private static let chosen = Mutex<String?>(nil)

    /// What the reader picked, or nil for the device's own.
    public static var tag: String? { chosen.withLock { $0 } }

    /// Changes the language for every lookup made after this returns.
    public static func choose(_ tag: String?) {
        chosen.withLock { $0 = tag }
    }

    /// A language named in itself. A reader looking for Deutsch is not helped by "German".
    public static func name(of tag: String) -> String {
        let locale = Locale(identifier: tag)
        let name = locale.localizedString(forLanguageCode: tag) ?? tag
        return name.prefix(1).uppercased(with: locale) + name.dropFirst()
    }
}

extension Locale {
    /// The locale every string in StoryArc resolves against.
    ///
    /// The reader's choice when there is one, and the device's otherwise. `autoupdatingCurrent`
    /// rather than `current` so a language changed in system settings is followed without a
    /// relaunch, which is the other half of what `localization` asks for.
    ///
    /// **The choice moves the language over the device's own locale, rather than replacing it.**
    /// A bare tag carries a region too: `Locale(identifier: "en")` means English *in the United
    /// States*, so a reader in the United Kingdom who picked English got the American date order
    /// and a 12-hour clock on a device set to 24. `localization` gives a date "the device's
    /// locale, calendar and time-zone conventions" and a size "locale digit grouping and unit
    /// conventions", and only its Sorting scenario names the interface language. So the region,
    /// the calendar, the clock and the numbering system stay the device's, and the language is
    /// the one field the choice sets. The script goes with the language: a device reading
    /// Simplified Chinese does not hand `Hans` to French.
    public static var storyArc: Locale {
        guard let tag = InterfaceLanguage.tag else { return .autoupdatingCurrent }
        var components = Locale.Components(locale: .autoupdatingCurrent)
        components.languageComponents.languageCode = Locale.LanguageCode(tag)
        components.languageComponents.script = nil
        return Locale(components: components)
    }
}
