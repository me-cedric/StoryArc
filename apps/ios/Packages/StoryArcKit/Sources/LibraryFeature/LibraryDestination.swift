public import StoryArcCore

/// Where the app can send a reader.
///
/// Three, permanently: what you are in the middle of, everything you have, and what
/// works on a plane. The `navigation-shell` capability's load-bearing sentence is that
/// this list "does not change when sources are added or removed", which is why
/// ``all(for:)`` takes the registry and ignores it — the signature is the promise, and
/// `LibraryDestinationTests` is what holds it to it.
///
/// It replaces `SidebarDestination`, which built itself as *library → one row per
/// browsable source → shelves*. Every catalogue, Kavita server and share a reader added
/// became a place they could go, so their own navigation said *Kavita* to them, and a
/// reader with four servers had a navigation control at the platform's ceiling. Origin is
/// not a destination; it belongs on a publication's own page and on a screen in Settings.
///
/// Search is deliberately absent. It is not a destination but a *role* — `Tab(role:
/// .search)` on iOS, a field at the top of the surface on Android — so the shell asks the
/// platform for it rather than listing it here. Android's own destination type holds the
/// same three cases in the same order.
public enum LibraryDestination: Hashable, Sendable, CaseIterable, Identifiable {
    /// The editorial surface: what the reader is in the middle of.
    case home
    /// The exhaustive shelf, over every source at once.
    case library
    /// Everything readable with no network at all.
    case onDevice

    public var id: Self { self }

    /// The SF Symbol each destination is drawn with, so the tab bar and any other
    /// presentation of the set agree without either of them choosing for itself.
    public var symbolName: String {
        switch self {
        case .home: "house"
        case .library: "books.vertical"
        case .onDevice: "arrow.down.circle"
        }
    }

    /// The destinations offered to a reader with these sources configured.
    ///
    /// The parameter is not read. It is kept because the question — *what does adding a
    /// server do to my navigation?* — is the one this capability exists to answer, and an
    /// answer that cannot be called with a registry cannot be tested against one.
    public static func all(for sources: [Source]) -> [LibraryDestination] {
        _ = sources
        return allCases
    }
}

/// Which face of the library one ``LibraryView`` is showing.
///
/// Two of the three destinations are the same screen over a different set — the shelf and
/// the on-device shelf draw the same grid, the same cells and the same reader — and
/// search is that screen with the field presented and the chrome out of the way. One view
/// rather than three copies of a branch, which is how one copy ends up showing the wrong
/// thing.
public enum LibrarySurface: Hashable, Sendable {
    /// Everything the app holds metadata for, from every source.
    case shelf
    /// Only what this device can open with no network at all.
    case onDevice
    /// The same shelf, narrowed by what the reader typed.
    case search
}
