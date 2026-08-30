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
}
