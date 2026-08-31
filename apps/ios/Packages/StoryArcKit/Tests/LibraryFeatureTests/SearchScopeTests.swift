import Foundation
import Testing

@testable import LibraryFeature
@testable import StoryArcCore

/// What search is *about to search*, and the one narrowing a reader on a train wants.
///
/// `library-browsing`'s *The scope is stated, and can be narrowed*: the screen "states whether
/// it is searching everything or only what is on the device", a reader "can narrow it to what
/// is on the device, and widen it again, without leaving the screen", and "the choice persists
/// until changed".
///
/// And the clause that makes it more than a filter — *Searching with every source
/// unreachable*: "narrowing to what is on the device removes that notice, **because nothing is
/// then being waited for**". A scope that only hid rows would leave the fan-out running and
/// the notice up, which is the failure these cases are for.
@Suite("Search scope")
struct SearchScopeTests {

    private func publication(_ title: String) -> Publication {
        Publication(
            identity: PublicationIdentity(contentDigest: title),
            format: .cbz,
            displayTitle: title,
            origin: .inferred
        )
    }

    // MARK: - The type is the library's own

    @Test("The two scopes are the axis the shelf already has, not a second vocabulary")
    func scopeReusesTheAvailabilityAxis() {
        // `LibraryAvailability` already means exactly this, already says it in four
        // languages, and already answers `keeps(_:)` the way `LibrarySurface.onDevice`
        // answers it. A `SearchScope` enum beside it would be two names for one idea, and
        // the two would drift on the day one of them gained a third case.
        #expect(LibraryAvailability.allCases == [.everywhere, .onThisDevice])
    }

    @Test("The search scope is written down somewhere of its own")
    func scopeHasItsOwnKey() {
        // Not the shelf's key. Narrowing a search to what is on the device must not narrow
        // the shelf a reader goes back to — `navigation-shell` promises they "return to the
        // destination they were on, with its scroll position and filters intact".
        #expect(LibraryAvailability.searchScopeKey != LibraryAvailability.storageKey)
        #expect(!LibraryAvailability.searchScopeKey.isEmpty)
    }

    // MARK: - What each scope keeps

    @Test("Everything keeps a row from anywhere")
    func everywhereKeepsEverything() {
        #expect(LibraryAvailability.everywhere.keeps(URL(string: "https://example.test/a.cbz")))
        #expect(LibraryAvailability.everywhere.keeps(URL(fileURLWithPath: "/tmp/a.cbz")))
        #expect(LibraryAvailability.everywhere.keeps(nil))
    }

    @Test("On this device keeps only what opens with no network")
    func onDeviceKeepsFilesOnly() {
        #expect(LibraryAvailability.onThisDevice.keeps(URL(fileURLWithPath: "/tmp/a.cbz")))
        #expect(LibraryAvailability.onThisDevice.keeps(URL(string: "https://example.test/a.cbz")) == false)
        // A publication the app has no location for cannot be opened on a plane, whatever
        // else is true of it.
        #expect(LibraryAvailability.onThisDevice.keeps(nil) == false)
    }

    // MARK: - Narrowing stops the asking, not just the showing

    @Test("Narrowing to the device asks no server at all")
    func narrowingAsksNobody() {
        let registry = SourceRegistry(sources: [
            Source(displayName: "Reading Room", kind: .kavitaServer),
            Source(displayName: "Attic", kind: .opdsCatalog),
        ])

        #expect(LibraryAvailability.everywhere.sourcesToAsk(in: registry).isEmpty == false)
        #expect(LibraryAvailability.onThisDevice.sourcesToAsk(in: registry).isEmpty)
    }

    @Test(
        "A source with no search endpoint is never asked, at either scope",
        arguments: [SourceKind.localFolder, SourceKind.networkShare]
    )
    func endpointlessSourcesAreNeverAsked(kind: SourceKind) {
        // Not a scope rule, and the reason is worth pinning: a folder and an SMB share have
        // no search endpoint, and `RemoteSearch.answers` has always said so — a first
        // version of this suite assumed a share was asked and was wrong. Asserted here so a
        // change to the scope cannot quietly start asking one.
        let registry = SourceRegistry(sources: [Source(displayName: "Comics", kind: kind)])

        #expect(LibraryAvailability.everywhere.sourcesToAsk(in: registry).isEmpty)
        #expect(LibraryAvailability.onThisDevice.sourcesToAsk(in: registry).isEmpty)
    }

    // MARK: - Rows

    @Test("Narrowing drops the rows that need a network, and keeps the rest")
    func narrowingFiltersRows() {
        let here = publication("Fine Print")
        let away = publication("Glasshouse")
        let locations: [Publication.ID: URL] = [
            here.id: URL(fileURLWithPath: "/tmp/fine-print.cbz"),
            away.id: URL(string: "https://example.test/glasshouse.cbz")!,
        ]

        let kept = LibraryAvailability.onThisDevice.keeping([here, away]) { locations[$0.id] }

        #expect(kept.map(\.displayTitle) == ["Fine Print"])
    }

    @Test("Widening again gives every row back")
    func wideningRestoresRows() {
        // "and widen it again, without leaving the screen". The filter is a projection over
        // the same set rather than a destructive narrowing, so widening cannot lose a row.
        let here = publication("Fine Print")
        let away = publication("Glasshouse")
        let locations: [Publication.ID: URL] = [
            here.id: URL(fileURLWithPath: "/tmp/fine-print.cbz"),
            away.id: URL(string: "https://example.test/glasshouse.cbz")!,
        ]

        let kept = LibraryAvailability.everywhere.keeping([here, away]) { locations[$0.id] }

        #expect(kept.count == 2)
    }
}
