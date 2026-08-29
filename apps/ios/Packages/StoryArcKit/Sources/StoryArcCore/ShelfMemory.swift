public import Foundation

/// Which family of publication a stored theme belongs to.
///
/// `reading-themes`: a theme set on a reflowable publication "does not change the
/// theme used for comics or fixed-layout publications, which have their own
/// default". Two scopes rather than one, because the two are read differently — a
/// line height means nothing to a page of artwork, and a reader who wants cream
/// paper for novels may well want black behind a comic.
public enum ThemeScope: String, Sendable, Codable, CaseIterable {
    case reflowable
    case fixedLayout
}

/// Everything a shelf is read with.
///
/// The theme *and* the typography, because a reader who moved the line height chose
/// a preset and a deviation from it, and storing only the preset would silently put
/// that deviation back on the next open — losing work they can see they did.
///
/// The page transition is here for the reason `comic-reader` gives: mode persistence
/// is word for word the same rule as theme persistence — per series, with a global
/// default, and comics independent of reflowable. One store, or two that have to be
/// kept in step.
public struct ShelfSettings: Sendable, Equatable, Codable {
    public var theme: ReadingTheme
    public var values: ThemeValues
    /// What the reader chose, not necessarily what runs. `page-transitions` is
    /// explicit that a stored Curl survives being opened on a device without one.
    public var transition: PageTransition
    /// `nil` means "whatever the publication implies", which is the default and the
    /// only value that can follow a webtoon into vertical without being told.
    public var scrollAxis: ScrollAxis?
    /// `nil` means "whatever the publication's metadata declares", for the same reason
    /// the axis above defaults to nothing: it is the only value that can follow a manga
    /// into right-to-left unprompted. `comic-reader` remembers an override "for the
    /// series", and per series is exactly what this store is.
    public var readingDirection: ReadingDirection?
    /// What to do to a page before it is shown. `comic-reader` requires an adjustment to
    /// apply "to the series and [not be] applied globally", which is what this store is.
    public var adjustments: ImageAdjustments

    /// - Parameter values: the typography. Defaults to the preset's own, which is
    ///   what an unmodified theme means.
    public init(
        theme: ReadingTheme = ReadingTheme(),
        values: ThemeValues? = nil,
        transition: PageTransition = .slide,
        scrollAxis: ScrollAxis? = nil,
        readingDirection: ReadingDirection? = nil,
        adjustments: ImageAdjustments = ImageAdjustments()
    ) {
        self.theme = theme
        self.values = values ?? theme.preset.values
        self.transition = transition
        self.scrollAxis = scrollAxis
        self.readingDirection = readingDirection
        self.adjustments = adjustments
    }

    /// Decodes what is there and defaults what is not.
    ///
    /// Swift's synthesised decoder fails on a missing key even where the property has
    /// a default, so a build that adds a field could not read what an earlier build
    /// wrote. This is the same forgiveness Android gets from `ignoreUnknownKeys`, and
    /// it matters for the same reason: losing a reader's settings is a poor trade for
    /// a stricter decoder.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let theme = try container.decodeIfPresent(ReadingTheme.self, forKey: .theme) ?? ReadingTheme()
        self.init(
            theme: theme,
            values: try container.decodeIfPresent(ThemeValues.self, forKey: .values),
            transition: try container.decodeIfPresent(PageTransition.self, forKey: .transition) ?? .slide,
            scrollAxis: try container.decodeIfPresent(ScrollAxis.self, forKey: .scrollAxis),
            readingDirection: try container.decodeIfPresent(
                ReadingDirection.self, forKey: .readingDirection
            ),
            adjustments: try container.decodeIfPresent(ImageAdjustments.self, forKey: .adjustments)
                ?? ImageAdjustments()
        )
    }
}

extension ShelfSettings {
    /// The same settings with a different page transition.
    public func settingTransition(_ transition: PageTransition) -> ShelfSettings {
        var copy = self
        copy.transition = transition
        return copy
    }

    /// The same settings with different image adjustments.
    public func settingAdjustments(_ adjustments: ImageAdjustments) -> ShelfSettings {
        var copy = self
        copy.adjustments = adjustments
        return copy
    }

    /// The same settings read the other way round.
    ///
    /// Unlike the axis below this changes nothing else: the direction is not a mode, and
    /// a reader who turned a wrongly tagged manga around has not asked for a different
    /// page transition as well.
    public func settingReadingDirection(_ direction: ReadingDirection) -> ShelfSettings {
        var copy = self
        copy.readingDirection = direction
        return copy
    }

    /// The same settings with the scroll axis overridden, and Scroll selected.
    ///
    /// Both at once, because a reader who picks an axis has picked Scroll — an axis
    /// that took effect only after a second choice would look like it did nothing.
    public func settingScrollAxis(_ axis: ScrollAxis) -> ShelfSettings {
        var copy = self
        copy.scrollAxis = axis
        copy.transition = .scroll(axis)
        return copy
    }
}

/// What the reader has chosen, remembered at the level they would expect.
///
/// `reading-themes` asks for three things that are one data structure: a theme
/// applies to every publication in the same series; a global default covers series
/// never opened; and changing that default does not overwrite a per-series choice
/// already made. The third falls out of keeping the two apart rather than out of any
/// logic — `settingDefault` cannot reach a shelf entry because it does not touch
/// that dictionary.
public struct ShelfMemory: Sendable, Equatable, Codable {
    /// Per shelf, keyed by scope and shelf together. A series called "Bone" can hold
    /// both a comic and an ebook, and the two must not share an entry.
    private var shelves: [String: ShelfSettings]

    /// The fallback for a shelf never opened, one per scope.
    private var defaults: [String: ShelfSettings]

    public init() {
        shelves = [:]
        defaults = [:]
    }

    /// The key a publication remembers its theme under.
    ///
    /// Its series where it has one, and its own identity where it does not — a
    /// standalone book is a series of one. Keying a standalone book to the global
    /// default instead would mean reading one novel in sepia changed every other
    /// book in the library.
    public static func shelf(series: String?, identity: String) -> String {
        let trimmed = series?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? identity : trimmed
    }

    /// The theme for a shelf: its own if it has one, else the scope's default, else
    /// the built-in one.
    public func theme(for scope: ThemeScope, shelf: String) -> ShelfSettings {
        shelves[key(scope, shelf)] ?? defaults[scope.rawValue] ?? ShelfSettings()
    }

    /// The scope's default on its own, for a settings screen to show and change.
    public func `default`(for scope: ThemeScope) -> ShelfSettings {
        defaults[scope.rawValue] ?? ShelfSettings()
    }

    /// Remembers a choice made while reading, for this shelf alone.
    public func remembering(
        _ stored: ShelfSettings,
        for scope: ThemeScope,
        shelf: String
    ) -> ShelfMemory {
        var copy = self
        copy.shelves[key(scope, shelf)] = stored
        return copy
    }

    /// Changes what a shelf never opened will get.
    ///
    /// `reading-themes`: this "applies to publications opened from then on and does
    /// not overwrite a per-series choice already made" — which is why it writes to a
    /// different dictionary rather than sweeping the first one.
    public func settingDefault(_ stored: ShelfSettings, for scope: ThemeScope) -> ShelfMemory {
        var copy = self
        copy.defaults[scope.rawValue] = stored
        return copy
    }

    /// Forgets every scope's default, and nothing else.
    ///
    /// What "reset settings to defaults" has to mean here. `settings-and-about` requires
    /// the reset to state that "sources, downloads, and reading progress are not
    /// affected", and a reader's *per-series* choices are none of those three but are
    /// equally not settings — they are decisions made while reading. So a reset returns
    /// what the settings screen can set and leaves what the reader set in place.
    public func clearingDefaults() -> ShelfMemory {
        var copy = self
        copy.defaults = [:]
        return copy
    }

    /// Whether this shelf has a choice of its own, as opposed to inheriting one.
    public func remembers(scope: ThemeScope, shelf: String) -> Bool {
        shelves[key(scope, shelf)] != nil
    }

    private func key(_ scope: ThemeScope, _ shelf: String) -> String {
        "\(scope.rawValue)/\(shelf)"
    }
}
