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

    public func layout() -> LibraryLayout {
        LibraryLayout(rawValue: defaults.string(forKey: layoutKey) ?? "") ?? .grid
    }

    public func save(_ layout: LibraryLayout) {
        defaults.set(layout.rawValue, forKey: layoutKey)
    }
}
