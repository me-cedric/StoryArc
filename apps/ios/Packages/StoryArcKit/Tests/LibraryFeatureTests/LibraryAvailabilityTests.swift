import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// The axis the library is narrowed on.
///
/// `library-browsing` replaced origin with availability as the library's primary axis:
/// "a reader filters by *can I read this now*, not by which server answered". The rule is
/// small and the two things that can go wrong with it are quiet — a remote publication
/// counted as local, and a shelf that shrinks when a source goes down — so both are
/// asserted here rather than looked for in a screenshot.
@Suite("Library availability")
struct LibraryAvailabilityTests {

    @Test("Everywhere keeps a publication wherever it lives, including nowhere yet")
    func everywhereKeepsEverything() {
        #expect(LibraryAvailability.everywhere.keeps(URL(fileURLWithPath: "/comics/a.cbz")))
        #expect(LibraryAvailability.everywhere.keeps(URL(string: "https://example.org/a.cbz")))
        #expect(LibraryAvailability.everywhere.keeps(nil))
    }

    @Test("On this device keeps only what opens with no network")
    func onThisDeviceKeepsOnlyLocalFiles() {
        // A folder the reader picked counts as much as a download the app fetched: a reader
        // on a plane does not care which of the two put the file there.
        #expect(LibraryAvailability.onThisDevice.keeps(URL(fileURLWithPath: "/comics/a.cbz")))
        #expect(!LibraryAvailability.onThisDevice.keeps(URL(string: "https://example.org/a.cbz")))
        #expect(!LibraryAvailability.onThisDevice.keeps(nil))
    }

    @Test("Everywhere is the setting a reader who has never chosen one gets")
    func defaultIsEverywhere() {
        // The whole library, not a narrowed one. A first launch that opened on "on this
        // device" would show an empty shelf to a reader who had just added a server.
        #expect(LibraryAvailability(rawValue: "") == nil)
        #expect(LibraryAvailability.allCases.first == .everywhere)
    }

    @Test("Widening restores the whole shelf in the order it was in")
    func wideningRestoresTheShelf() {
        // The property this axis exists for, and until 2026-09-05 it was asserted on Android
        // only — `narrowedTo` is a function over a list there, and iOS's narrowing lived
        // inside a computed `var` on a `View` extension where no host test could reach it.
        // Task 3.1's seam is `narrowing(_:location:)`, and this is what it was cut for.
        let here = publication(named: "Here")
        let away = publication(named: "Away")
        let alsoHere = publication(named: "Also here")
        let shelf = [away, here, alsoHere]
        let location: (Publication) -> URL? = { item in
            item.id == away.id
                ? URL(string: "https://example.org/a.cbz")
                : URL(fileURLWithPath: "/comics/\(item.id).cbz")
        }

        let narrowed = LibraryAvailability.onThisDevice.narrowing(shelf, location: location)
        #expect(narrowed.map(\.displayTitle) == ["Here", "Also here"])

        // Widened: the same list, in the order it was handed over. Not re-sorted, not
        // re-scanned, not re-fetched — the requirement says "without re-scanning anything",
        // and the only honest way to show that from a host test is that the order a caller
        // set comes back untouched.
        let widened = LibraryAvailability.everywhere.narrowing(shelf, location: location)
        #expect(widened.map(\.displayTitle) == ["Away", "Here", "Also here"])
    }

    @Test("A publication the app has no location for at all is not on this device")
    func nowhereIsNotHere() {
        // A row that reached the shelf from a server's metadata and has never been
        // downloaded. `keeps(nil)` says so one publication at a time; this says it over a
        // list, which is where a `nil` is easiest to let slip through a `compactMap`.
        let shelf = [publication(named: "Ghost")]

        #expect(LibraryAvailability.onThisDevice.narrowing(shelf) { _ in nil }.isEmpty)
        #expect(LibraryAvailability.everywhere.narrowing(shelf) { _ in nil }.count == 1)
    }

    @Test("Narrowing an empty shelf is an empty shelf, not a crash and not the whole library")
    func nothingNarrowsToNothing() {
        #expect(LibraryAvailability.onThisDevice.narrowing([]) { _ in nil }.isEmpty)
        #expect(LibraryAvailability.everywhere.narrowing([]) { _ in nil }.isEmpty)
    }

    private func publication(named title: String) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/comics/\(title).cbz"),
            format: .cbz,
            displayTitle: title,
            origin: .inferred
        )
    }

    @Test("The stored value is a name, so a reordered enum cannot change what it means")
    func storedByName() {
        #expect(LibraryAvailability.everywhere.rawValue == "everywhere")
        #expect(LibraryAvailability.onThisDevice.rawValue == "onThisDevice")
        #expect(LibraryAvailability.storageKey == "app.storyarc.libraryAvailability")
    }
}

/// That a publication which cannot be opened right now is dimmed rather than removed.
///
/// `library-browsing`: it "stays in the library, dimmed", and is "never removed from the
/// shelf, because a library that shrinks when the Wi-Fi drops reads as data loss".
@Suite("Unreadable publications stay on the shelf")
struct UnreadableDimmingTests {

    private func publication(sourceID: UUID? = nil) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/remote/\(UUID().uuidString)"),
            format: .cbz,
            displayTitle: "Fixture",
            origin: .inferred,
            sourceID: sourceID
        )
    }

    private func downedLibrary() -> Source {
        var source = Source(displayName: "Attic", kind: .networkShare)
        source.state = .unreachable(since: .now)
        return source
    }

    @Test("A publication whose bytes are on the device is readable whatever its library says")
    func localFilesAreAlwaysReadable() {
        let source = downedLibrary()

        #expect(
            LibraryAvailability.isReadableNow(
                publication(sourceID: source.id),
                location: URL(fileURLWithPath: "/comics/a.cbz"),
                registry: SourceRegistry(sources: [source])
            )
        )
    }

    @Test("A publication only a downed library holds is not readable")
    func unreachableSourcesAreNotReadable() {
        let source = downedLibrary()

        #expect(
            !LibraryAvailability.isReadableNow(
                publication(sourceID: source.id),
                location: nil,
                registry: SourceRegistry(sources: [source])
            )
        )
    }

    @Test("A connected library's publications are readable even before they are downloaded")
    func connectedSourcesAreReadable() {
        var source = Source(displayName: "Attic", kind: .opdsCatalog)
        source.state = .connected

        #expect(
            LibraryAvailability.isReadableNow(
                publication(sourceID: source.id),
                location: nil,
                registry: SourceRegistry(sources: [source])
            )
        )
    }

    @Test("A library still being asked is not yet a library that failed")
    func connectingIsNotAVerdict() {
        // The shelf probes every network library when it appears. Dimming on `connecting`
        // would grey the whole shelf on every launch and un-grey it a second later, which
        // tells the reader their library is broken and then that it is not.
        let source = Source(displayName: "Attic", kind: .opdsCatalog)
        #expect(source.state == .connecting)

        #expect(
            LibraryAvailability.isReadableNow(
                publication(sourceID: source.id),
                location: nil,
                registry: SourceRegistry(sources: [source])
            )
        )
    }

    @Test("A library that wants a password is dimmed, like one that cannot be reached")
    func unauthorizedSourcesAreNotReadable() {
        var source = Source(displayName: "Attic", kind: .kavitaServer)
        source.state = .unauthorized(reason: "Sign in again")

        #expect(
            !LibraryAvailability.isReadableNow(
                publication(sourceID: source.id),
                location: nil,
                registry: SourceRegistry(sources: [source])
            )
        )
    }

    @Test("A publication no library claims is readable, because it was handed over")
    func unattributedPublicationsAreReadable() {
        // A file another app opened in StoryArc has no source, and attributing it to
        // whichever library happens to be down would be a guess that dimmed it for nothing.
        #expect(
            LibraryAvailability.isReadableNow(
                publication(sourceID: nil),
                location: nil,
                registry: SourceRegistry()
            )
        )
    }

    @Test("Every source kind is answered from the download record alone, none of them asked")
    func everySourceKindIsAnsweredWithoutAsking() {
        // Task 0.3's deliverable: one publication of each of the four kinds, decided with
        // no network. `SourceKind.localFolder` was the one kind this suite never used, and
        // it is the interesting one — on Android the kind changes the answer, and the
        // reason it does not here is worth pinning rather than assuming. `isReadableNow`
        // reads `location` and `Source.state`; it never touches `kind`, and no path out of
        // it can reach a source. So a downed folder and a downed server agree, and so do a
        // connected folder and a connected catalogue.
        for kind in SourceKind.allCases {
            var down = Source(displayName: "Down", kind: kind)
            down.state = .unreachable(since: .now)
            var up = Source(displayName: "Up", kind: kind)
            up.state = .connected
            let registry = SourceRegistry(sources: [down, up])

            // Bytes on the device outrank whatever the library is doing, for every kind.
            #expect(
                LibraryAvailability.isReadableNow(
                    publication(sourceID: down.id),
                    location: URL(fileURLWithPath: "/comics/a.cbz"),
                    registry: registry
                ),
                "\(kind.rawValue): a downloaded publication is readable with the library down"
            )
            // And with no bytes, the library's state is the whole answer — for every kind.
            #expect(
                !LibraryAvailability.isReadableNow(
                    publication(sourceID: down.id),
                    location: nil,
                    registry: registry
                ),
                "\(kind.rawValue): nothing on the device and a downed library is not readable"
            )
            #expect(
                LibraryAvailability.isReadableNow(
                    publication(sourceID: up.id),
                    location: nil,
                    registry: registry
                ),
                "\(kind.rawValue): a reachable library's publications are readable"
            )
        }
    }

    @Test("Being unreadable never removes a publication from what the shelf lists")
    func dimmingIsNotAFilter() {
        // The requirement's own sentence: "it is never removed from the shelf, because a
        // library that shrinks when the Wi-Fi drops reads as data loss". The availability
        // axis is what narrows the shelf; reachability only ever dims a cell.
        let source = downedLibrary()
        let item = publication(sourceID: source.id)

        #expect(!LibraryAvailability.isReadableNow(item, location: nil, registry: SourceRegistry(sources: [source])))
        #expect(LibraryAvailability.everywhere.keeps(nil))
    }
}
