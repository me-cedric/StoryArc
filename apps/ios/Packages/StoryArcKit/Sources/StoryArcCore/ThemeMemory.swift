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

/// A theme and the typography in force under it.
///
/// Both halves. A reader who moved the line height chose a preset *and* a deviation
/// from it, and storing only the preset would silently put that deviation back on
/// the next open — losing work the reader can see they did.
public struct StoredTheme: Sendable, Equatable, Codable {
    public var theme: ReadingTheme
    public var values: ThemeValues

    /// - Parameter values: the typography. Defaults to the preset's own, which is
    ///   what an unmodified theme means.
    public init(theme: ReadingTheme = ReadingTheme(), values: ThemeValues? = nil) {
        self.theme = theme
        self.values = values ?? theme.preset.values
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
public struct ThemeMemory: Sendable, Equatable, Codable {
    /// Per shelf, keyed by scope and shelf together. A series called "Bone" can hold
    /// both a comic and an ebook, and the two must not share an entry.
    private var shelves: [String: StoredTheme]

    /// The fallback for a shelf never opened, one per scope.
    private var defaults: [String: StoredTheme]

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
    public func theme(for scope: ThemeScope, shelf: String) -> StoredTheme {
        shelves[key(scope, shelf)] ?? defaults[scope.rawValue] ?? StoredTheme()
    }

    /// The scope's default on its own, for a settings screen to show and change.
    public func `default`(for scope: ThemeScope) -> StoredTheme {
        defaults[scope.rawValue] ?? StoredTheme()
    }

    /// Remembers a choice made while reading, for this shelf alone.
    public func remembering(
        _ stored: StoredTheme,
        for scope: ThemeScope,
        shelf: String
    ) -> ThemeMemory {
        var copy = self
        copy.shelves[key(scope, shelf)] = stored
        return copy
    }

    /// Changes what a shelf never opened will get.
    ///
    /// `reading-themes`: this "applies to publications opened from then on and does
    /// not overwrite a per-series choice already made" — which is why it writes to a
    /// different dictionary rather than sweeping the first one.
    public func settingDefault(_ stored: StoredTheme, for scope: ThemeScope) -> ThemeMemory {
        var copy = self
        copy.defaults[scope.rawValue] = stored
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
