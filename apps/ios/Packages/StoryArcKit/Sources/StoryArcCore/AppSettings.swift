public import Foundation

/// Everything Settings holds that is not per-shelf and not per-source.
///
/// Deliberately small. `settings-and-about` names seven groups, and most of them own
/// nothing of their own: Sources belongs to the connectors, Downloads to
/// `offline-downloads`, Reading defaults to ``ShelfMemory``'s per-scope defaults, and
/// Privacy has nothing to toggle at all — its whole point is that the app has no
/// backend to opt out of. What is left is this.
///
/// One value type rather than four keys, for the reason ``ShelfMemory`` is one blob:
/// a screen that reads five settings to draw one row should read them together, and a
/// reset should be an assignment rather than four deletions.
public struct AppSettings: Sendable, Equatable, Codable {
    /// Light, dark, or whatever the device says. Defaults to the device.
    public var appearance: AppearanceMode

    /// A BCP-47 tag, or `nil` to follow the system.
    ///
    /// `localization` requires the app to follow the system language and to allow an
    /// override; `nil` is the difference between "the reader has not chosen" and "the
    /// reader chose the language the system happens to be set to today".
    public var language: String?

    /// Whether the volume buttons turn pages.
    ///
    /// Off by default, and `page-transitions` is the reason it is a setting at all:
    /// volume keys that silently stop changing the volume are a defect rather than a
    /// feature, so this is opt-in and stays opt-in.
    public var turnPagesWithVolumeButtons: Bool

    /// Whether the reading theme follows the app's appearance.
    ///
    /// Off by default, because `settings-and-about` is explicit that the two are
    /// separate: "a dark app chrome with a paper-white page is a legitimate
    /// preference". This is the "single opt-in setting" the same requirement then
    /// allows for readers who want them linked.
    public var linkReadingThemeToAppearance: Bool

    public init(
        appearance: AppearanceMode = .system,
        language: String? = nil,
        turnPagesWithVolumeButtons: Bool = false,
        linkReadingThemeToAppearance: Bool = false
    ) {
        self.appearance = appearance
        self.language = language
        self.turnPagesWithVolumeButtons = turnPagesWithVolumeButtons
        self.linkReadingThemeToAppearance = linkReadingThemeToAppearance
    }

    /// Decodes what is there and defaults what is not.
    ///
    /// Swift's synthesised decoder fails on a missing key even where the property has a
    /// default, so a build that adds a setting could not read what an earlier build
    /// wrote. Losing a reader's settings is a poor trade for a stricter decoder.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            appearance: try container.decodeIfPresent(AppearanceMode.self, forKey: .appearance)
                ?? .system,
            language: try container.decodeIfPresent(String.self, forKey: .language),
            turnPagesWithVolumeButtons: try container.decodeIfPresent(
                Bool.self, forKey: .turnPagesWithVolumeButtons
            ) ?? false,
            linkReadingThemeToAppearance: try container.decodeIfPresent(
                Bool.self, forKey: .linkReadingThemeToAppearance
            ) ?? false
        )
    }

    /// What a reset returns to.
    ///
    /// `settings-and-about` requires a reset to state that "sources, downloads, and
    /// reading progress are not affected", and this type is why that statement is true
    /// rather than merely promised: it holds none of them.
    public static let defaults = AppSettings()
}
