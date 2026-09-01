public import SwiftUI

public import StoryArcCore

/// What the shelf is narrowed to, on the axis a reader actually asks about.
///
/// `library-browsing`: the library is narrowed by **availability** — everything, or only
/// what can be read with no network — "as its primary axis". Origin was the axis before,
/// and it was the wrong question: a reader on a train wants to know whether a book opens,
/// not which machine answered for it.
///
/// Held by ``LibraryView`` rather than by ``LibraryModel``: the model's `LibraryQuery` is
/// the contract both platforms share, and adding a case to it is a change to `StoryArcCore`
/// and to Android's mirror of it. This is one shelf choice with a `UserDefaults` key of its
/// own, which is what "the choice persists until changed" needs and no more.
enum LibraryAvailability: String, CaseIterable, Sendable {
    /// Everything the app holds metadata for, reachable or not.
    case everywhere
    /// Only what opens with no network at all.
    case onThisDevice

    /// Reuses "Everywhere", which the scope selector already said in four languages and
    /// which is the same promise on the new axis.
    var titleKey: LocalizedStringKey {
        switch self {
        case .everywhere: "library.scope.all"
        case .onThisDevice: "library.availability.onDevice"
        }
    }

    var symbolName: String {
        switch self {
        case .everywhere: "square.stack.3d.up"
        case .onThisDevice: "arrow.down.circle"
        }
    }

    /// Whether a publication at this location survives the narrowing.
    ///
    /// The same question ``LibrarySurface/onDevice`` asks, deliberately: everything the app
    /// can open from a file URL qualifies — a folder the reader picked as much as a
    /// download the app fetched — because a reader with no network does not care which of
    /// the two put the file there.
    func keeps(_ location: URL?) -> Bool {
        switch self {
        case .everywhere: true
        case .onThisDevice: location?.isFileURL == true
        }
    }

    /// Where the choice is written down. Its own key beside `LibraryPreferences`' keys, in
    /// the same `UserDefaults`, so nothing has to be migrated to add it.
    static let storageKey = "app.storyarc.libraryAvailability"

    /// Where the **search screen's** own choice is written down.
    ///
    /// A second key rather than the shelf's, because the two are the same question asked
    /// about different screens. `navigation-shell` promises a reader leaving search "return to
    /// the destination they were on, with its scroll position and filters intact" — and a
    /// shared key would have narrowing a search on a train silently narrow the shelf they go
    /// back to, which is a filter they never set and would have to find to undo.
    ///
    /// `library-browsing` asks the search choice to persist "until changed" in its own right,
    /// so it needs somewhere of its own to persist to.
    static let searchScopeKey = "app.storyarc.searchScope"

    /// The sources a search at this scope puts the question to.
    ///
    /// **This is the half a filter would miss**, and it is a requirement rather than an
    /// optimisation. `library-browsing`: narrowing to what is on the device "removes that
    /// notice, *because nothing is then being waited for*". A scope that only hid rows would
    /// leave the fan-out running and the could-not-answer notice up, so the reader who
    /// narrowed precisely to stop waiting would still be waiting.
    ///
    /// ``RemoteSearch/answers(_:)`` still decides who *can* be asked at all — a folder and an
    /// SMB share have no search endpoint at either scope. This decides who *is*.
    func sourcesToAsk(in registry: SourceRegistry) -> [Source] {
        switch self {
        case .everywhere: registry.sources.filter(RemoteSearch.answers)
        case .onThisDevice: []
        }
    }

    /// The publications that survive this narrowing.
    ///
    /// A projection over the same set rather than a destructive narrowing, which is what lets
    /// a reader "widen it again, without leaving the screen" and get every row back.
    ///
    /// `location` is a closure rather than a dictionary so the caller supplies the model's own
    /// ``LibraryModel/location(of:)`` in the app and a literal in a test — the shelf asks
    /// ``keeps(_:)`` exactly the same way in `LibraryContent`.
    func keeping(
        _ publications: [Publication],
        location: (Publication) -> URL?
    ) -> [Publication] {
        publications.filter { keeps(location($0)) }
    }

    /// Whether a publication can be opened right now.
    ///
    /// `library-browsing`: one that is neither on the device nor currently reachable "stays
    /// in the library, dimmed" — "never removed from the shelf, because a library that
    /// shrinks when the Wi-Fi drops reads as data loss". So this decides an opacity and
    /// never a filter, which is the distinction the requirement turns on.
    ///
    /// A publication no library claims is readable by definition: it came from a file
    /// another app handed over, and attributing it to whichever library happens to be down
    /// would be a guess that dimmed it for nothing.
    ///
    /// Static and free of the view for the reason the sectioning rule is: it is a decision,
    /// and a decision asked once per visible cell on every redraw is worth asserting
    /// directly rather than reading off a screenshot.
    static func isReadableNow(
        _ publication: Publication,
        location: URL?,
        registry: SourceRegistry
    ) -> Bool {
        if location?.isFileURL == true { return true }
        guard let id = publication.sourceID, let source = registry[id] else { return true }
        switch source.state {
        // `connecting` is not a verdict. The library probes every network source when it
        // appears, so treating "still asking" as "cannot be reached" would grey the whole
        // shelf on every launch and then un-grey it a second later — a flash that tells the
        // reader their library is broken and then that it is not.
        case .connected, .connecting: return true
        case .unreachable, .unauthorized: return false
        }
    }
}

// The control that used to stand here is gone, and where it went matters.
//
// `ScopeMenu` was a toolbar item of its own — one of six in `.primaryAction`, four of them an
// unlabelled glyph. `library-browsing` now asks that the choices a reader makes about the
// shelf be "reached through named menus rather than as separate unlabelled buttons", so the
// availability picker is a section of ``ViewMenu`` and this file keeps only the axis itself.
//
// **The axis did not become a filter by moving.** It is still the library's primary one:
// narrowing to one library is a filter — counted in ``LibraryNarrowing``'s badge and undone by
// *Clear filters* — and narrowing to what opens with no network is a mode the shelf is in,
// which is why it is not counted and why ``FilterMenu`` still resets it without listing it.
// ``ViewMenu``'s own glyph is what now keeps the requirement that the choice be "visible while
// it is active".
//
// *From*, a second picker this control once carried, is the reason that distinction is written
// down twice. Narrowing to one library was modelled here as a scope with a control in the
// toolbar; it silently narrowed the search as well, the filter menu's count did not know the
// field existed, and *Clear filters* left it set. It is a filter now, counted and cleared with
// everything else, and Android says the same in its own `FilterSection`.

/// Match groups, narrowed to a search scope.
///
/// An extension on the array rather than a method on ``LibraryAvailability``: what is being
/// narrowed is the *listing*, and the scope is the argument. `LibrarySearch` is the only
/// caller.
extension [MatchGroup] {
    /// The same match groups, narrowed to this scope.
    ///
    /// A group left empty is **dropped**, not kept with nothing in it: `library-browsing`
    /// groups results by match kind, and a heading over no rows would tell the reader their
    /// term matched a series when what it matched is a series they cannot open on a plane.
    func narrowed(
        to scope: LibraryAvailability,
        location: (Publication) -> URL?
    ) -> [MatchGroup] {
        compactMap { group in
            let kept = scope.keeping(group.publications, location: location)
            return kept.isEmpty ? nil : MatchGroup(kind: group.kind, publications: kept)
        }
    }
}
