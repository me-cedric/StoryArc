public import StoryArcCore

/// Where the app can send a reader.
///
/// Four, fixed: what you are in the middle of, everything you have, what works on a plane,
/// and the one surface that spans the sources. The `navigation-shell` capability's
/// load-bearing sentence is that this list "does not change when sources are added or
/// removed", which is why ``all(for:)`` takes the registry and ignores it — the signature
/// is the promise, and `LibraryDestinationTests` is what holds it to it. *Fixed* is the
/// promise; *three* never was.
///
/// It replaces `SidebarDestination`, which built itself as *library → one row per
/// browsable source → shelves*. Every catalogue, Kavita server and share a reader added
/// became a place they could go, so their own navigation said *Kavita* to them, and a
/// reader with four servers had a navigation control at the platform's ceiling. Origin is
/// not a destination; it belongs on a publication's own page and on a screen in Settings.
///
/// ## Search was deliberately absent, and is deliberately here
///
/// **The argument this comment used to make.** Search "is not a destination but a *role* —
/// `Tab(role: .search)` on iOS, a field at the top of the surface on Android — so the shell
/// asks the platform for it rather than listing it here." It was a good argument about
/// *listing*: a fourth row is a cost, and asking the platform for a well-known affordance
/// beats authoring one.
///
/// **Why it no longer holds.** It was answered by the wrong control. `Tab(role: .search)`
/// does not merely sit apart from the destinations — it *morphs the tab into a text field
/// in place*, confirmed on a device on 2026-08-31. So the bar changed shape under the
/// reader's thumb and there was nowhere to land: no screen, and therefore nothing that
/// could offer a reader something before they had typed. `navigation-shell` now states the
/// outcome rather than the control — search "SHALL be a place a reader arrives at, and no
/// control SHALL change shape or position to become it" — and a place needs a case here.
///
/// **And this app in particular.** One research pass argued search should stay a field
/// belonging to the library, because StoryArc's primary action is browsing a shelf.
/// Overruled for a reason about this app rather than about apps: publications arrive from a
/// device, a folder, an OPDS catalogue, a Kavita server and an SMB share, and *no shelf
/// shows all of them at once in a way a reader can scan*. Search is the only surface that
/// spans the sources. In an app whose library is one folder search is a filter; in this one
/// it is the way in.
///
/// Four sits inside Material's own range for both controls the mirrored side draws — 3–5
/// for the navigation bar, 3–7 for the collapsed rail — so nothing about the count is
/// strained. Android's own destination type holds the same four cases in the same order.
public enum LibraryDestination: Hashable, Sendable, CaseIterable, Identifiable {
    /// The editorial surface: what the reader is in the middle of.
    case home
    /// The exhaustive shelf, over every source at once.
    case library
    /// Everything readable with no network at all.
    case onDevice
    /// The one surface that spans every configured source, and a screen with something to
    /// offer before a letter is typed. Last, because it is the destination a reader goes to
    /// when the three shelves in front of it did not have the answer.
    case search

    public var id: Self { self }

    /// The SF Symbol each destination is drawn with, so the tab bar and any other
    /// presentation of the set agree without either of them choosing for itself.
    public var symbolName: String {
        switch self {
        case .home: "house"
        case .library: "books.vertical"
        case .onDevice: "arrow.down.circle"
        case .search: "magnifyingglass"
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
/// Three of the four destinations are the same screen over a different set — the shelf and
/// the on-device shelf draw the same grid, the same cells and the same reader — and
/// search is that screen with the field at the top of its own page. One view rather than
/// three copies of a branch, which is how one copy ends up showing the wrong thing.
public enum LibrarySurface: Hashable, Sendable {
    /// Everything the app holds metadata for, from every source.
    case shelf
    /// Only what this device can open with no network at all.
    case onDevice
    /// The same shelf, narrowed by what the reader typed.
    case search
}
