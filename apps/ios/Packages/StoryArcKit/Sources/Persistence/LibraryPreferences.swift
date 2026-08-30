public import Foundation

public import StoryArcCore

/// How the library was left, remembered across launches.
///
/// `library-browsing`: "when a user leaves the library and returns, active filters
/// are still applied", and a layout choice "persists per scope, so a dense list for
/// one library does not force it everywhere". Both are one small value read once at
/// launch, so they live in `UserDefaults` rather than the progress database —
/// opening SwiftData before the first screen to learn a sort order would be a
/// strange trade.
///
/// Not `Sendable`: `UserDefaults` is not, and claiming otherwise would be a lie the
/// compiler cannot catch. It is cheap to construct where it is needed. Android's
/// `LibraryPreferences` keeps the same values in `SharedPreferences`.
public struct LibraryPreferences {
    private let defaults: UserDefaults
    private let queryKey = "app.storyarc.libraryQuery"
    private let layoutKey = "app.storyarc.libraryLayout"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The stored query, or a fresh one.
    ///
    /// The search term is deliberately **not** restored. A filter is a decision
    /// that outlives a session; a half-typed search is not, and reopening the app
    /// to a library narrowed by a word typed yesterday reads as a bug.
    public func query() -> LibraryQuery {
        guard let data = defaults.data(forKey: queryKey),
              var stored = try? JSONDecoder().decode(LibraryQuery.self, from: data)
        else { return LibraryQuery() }
        stored.search = ""
        return stored
    }

    public func save(_ query: LibraryQuery) {
        var stored = query
        stored.search = ""
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: queryKey)
    }

    /// The layout for one scope.
    ///
    /// `library-browsing`: the choice "persists per scope, so a dense list for one library
    /// does not force it everywhere" — a reader who wants covers for their comics and a
    /// list for their server's catalogue gets both.
    ///
    /// One key per scope rather than one dictionary. A scope arrives and leaves with its
    /// source, and a dictionary would have to be pruned when a source is removed by
    /// something that currently has no reason to know this file exists.
    ///
    /// A scope never set falls back to what was stored before the layout was per scope, so
    /// a reader who chose the list is not handed the grid again by an upgrade.
    public func layout(for scope: LibraryScope = .allSources) -> LibraryLayout {
        if let stored = defaults.string(forKey: key(for: scope)),
           let layout = LibraryLayout(rawValue: stored) {
            return layout
        }
        return LibraryLayout(rawValue: defaults.string(forKey: layoutKey) ?? "") ?? .grid
    }

    public func save(_ layout: LibraryLayout, for scope: LibraryScope = .allSources) {
        defaults.set(layout.rawValue, forKey: key(for: scope))
    }

    private func key(for scope: LibraryScope) -> String {
        "\(layoutKey).\(scope.storageKey)"
    }
}
