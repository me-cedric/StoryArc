import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// The one line that makes five kinds of source read as one library.
///
/// It carries the whole argument of the revamp and it is one sentence, so it is asserted
/// rather than inspected. Two of these cases are the ones the proposal names as most likely
/// to be silently wrong: a removed source whose name is still on the screen, and the same
/// publication in two places where the line has to say which copy this page will open.
@Suite("Provenance")
struct PublicationProvenanceTests {

    private func publication(from sourceID: UUID? = nil) -> Publication {
        var made = Publication(
            identity: PublicationIdentity(normalizedPath: "/comics/Bone 1.cbz"),
            format: .cbz,
            displayTitle: "Bone #1",
            origin: .inferred
        )
        made.sourceID = sourceID
        return made
    }

    private func source(
        named name: String,
        state: SourceConnectionState = .connected
    ) -> Source {
        Source(displayName: name, kind: .kavitaServer, state: state)
    }

    @Test("A download says it is on this device, and names where it came from")
    func onDeviceNamesItsLibrary() {
        let library = source(named: "Attic")
        let line = PublicationProvenance.of(
            publication(from: library.id),
            isOnDevice: true,
            hasFile: true,
            source: library
        )

        #expect(line.home == .thisDevice)
        #expect(line.availability == .offline)
        // The copy this page opens is the one on the device; the server is the other place.
        #expect(line.alsoIn == "Attic")
    }

    /// The case the tasks single out: "this is the case that will silently render a stale
    /// name". A removed source is `nil` here because the registry no longer holds it.
    @Test("A download outlives its source, and stops naming it")
    func removedSourceIsNotNamed() {
        let line = PublicationProvenance.of(
            publication(from: UUID()),
            isOnDevice: true,
            hasFile: true,
            source: nil
        )

        #expect(line.home == .thisDevice)
        #expect(line.availability == .offline)
        #expect(line.alsoIn == nil)
    }

    @Test("A publication whose file is here reads as readable now")
    func reachableFileIsReadableNow() {
        let library = source(named: "Shelf")
        let line = PublicationProvenance.of(
            publication(from: library.id),
            isOnDevice: false,
            hasFile: true,
            source: library
        )

        #expect(line.home == .library(name: "Shelf"))
        #expect(line.availability == .now)
        #expect(line.alsoIn == nil)
    }

    @Test("A publication with no file, from a library that is answering, is not here yet")
    func connectedWithoutFileIsNotHere() {
        let library = source(named: "Attic")
        let line = PublicationProvenance.of(
            publication(from: library.id),
            isOnDevice: false,
            hasFile: false,
            source: library
        )

        #expect(line.home == .library(name: "Attic"))
        #expect(line.availability == .notHere)
    }

    @Test("A publication with no file, from a library that is away, says so")
    func unreachableWithoutFileIsNotAnswering() {
        let library = source(named: "Attic", state: .unreachable(since: .now))
        let line = PublicationProvenance.of(
            publication(from: library.id),
            isOnDevice: false,
            hasFile: false,
            source: library
        )

        #expect(line.home == .library(name: "Attic"))
        #expect(line.availability == .notAnswering)
    }

    /// A cached chapter stays readable while its server is away — the file wins over the
    /// connection, because the connection is not what the reader is about to use.
    @Test("A cached file stays readable while its library is away")
    func cachedFileBeatsAnUnreachableSource() {
        let library = source(named: "Attic", state: .unreachable(since: .now))
        let line = PublicationProvenance.of(
            publication(from: library.id),
            isOnDevice: false,
            hasFile: true,
            source: library
        )

        #expect(line.availability == .now)
    }

    @Test("A file the system handed over is on this device, not in a library")
    func unattributedFileIsHere() {
        let line = PublicationProvenance.of(
            publication(),
            isOnDevice: false,
            hasFile: true,
            source: nil
        )

        #expect(line.home == .thisDevice)
        #expect(line.availability == .offline)
    }

    @Test("A row with no source and no file names no library at all")
    func unattributedWithoutFile() {
        let line = PublicationProvenance.of(
            publication(),
            isOnDevice: false,
            hasFile: false,
            source: nil
        )

        #expect(line.home == .unattributed)
        #expect(line.availability == .notHere)
        #expect(line.alsoIn == nil)
    }

    // MARK: - The other reading of "in two places"

    /// Task 3.2's own case, and the one this platform had never answered: the *shelf* holds
    /// two rows for one publication, one from a picked folder and one from a server. Identity
    /// is stable across sources, so they share an id and differ only in `sourceID`.
    ///
    /// Android has answered this since it was written; iOS answered only the other half — a
    /// download plus the library it came from. Each was half of one requirement, and for a
    /// book downloaded from one server that also sits on a second they disagreed outright.
    @Test("Another library holding the same publication is named")
    func anotherLibraryIsNamed() {
        let nas = source(named: "Home NAS")
        let here = publication()
        let there = publication(from: nas.id)
        let registry = SourceRegistry(sources: [nas])

        #expect(
            PublicationProvenance.alsoHolding(here, in: [here, there], registry: registry)
                == "Home NAS"
        )
    }

    @Test("One copy is in one place, and the line says nothing about a second")
    func oneCopyIsNotElsewhere() {
        let nas = source(named: "Home NAS")
        let only = publication(from: nas.id)

        #expect(
            PublicationProvenance.alsoHolding(
                only,
                in: [only],
                registry: SourceRegistry(sources: [nas])
            ) == nil
        )
    }

    /// The same guard the removed-source case gets, from the other direction. A second row
    /// whose source the registry has forgotten is not a place the reader can be sent to, and
    /// naming it would be the stale-name failure this line is most likely to produce.
    @Test("A second copy whose source has been removed is not named")
    func aRemovedSecondSourceIsNotNamed() {
        let here = publication()
        let there = publication(from: UUID())

        #expect(
            PublicationProvenance.alsoHolding(here, in: [here, there], registry: SourceRegistry())
                == nil
        )
    }

    /// And the union, at the point it is composed: a downloaded copy names the library it
    /// came from, and where there is no such library the shelf's other row supplies the name.
    @Test("The two readings compose into one line")
    func theUnionIsWhatTheLineCarries() {
        let attic = source(named: "Attic")
        let downloaded = PublicationProvenance.of(
            publication(from: attic.id),
            isOnDevice: true,
            hasFile: true,
            source: attic,
            elsewhere: "Home NAS"
        )
        // The library it was fetched from wins the naming: it is the place the *reader*
        // chose, and the shelf's other row is a coincidence of identity.
        #expect(downloaded.alsoIn == "Attic")

        let imported = PublicationProvenance.of(
            publication(),
            isOnDevice: true,
            hasFile: true,
            source: nil,
            elsewhere: "Home NAS"
        )
        // No library to fetch from, so the other row is the only second place there is.
        #expect(imported.home == .thisDevice)
        #expect(imported.alsoIn == "Home NAS")
    }
}
