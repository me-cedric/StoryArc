import Foundation
import Testing

@testable import LibraryFeature
import Persistence
import StoryArcCore

/// What a local library reports about itself, and what it holds.
///
/// The 2026-09-02 sweep photographed *Your libraries* listing four sources, all reading
/// `0 titles` and all reading *Connecting* — including a local folder, which has nothing to
/// connect to — beside a shelf holding fourteen publications. Two defects wearing one frame.
///
/// **A local folder has no network state.** `sources` gives every source four states, and
/// three of them mean something to a folder: it can be read, it cannot, or its credential was
/// refused. `connecting` is the state of *waiting for an answer*, and a folder answers
/// immediately — `FileManager` either finds it or does not. Nothing ever asked, though:
/// state is deliberately never persisted, so every source loads as `connecting`, and the only
/// thing that resolved one was ``LibraryModel/probeNetworkSources(credentials:pins:)``, which
/// walks past local folders by design. A folder whose bookmark did not restore therefore sat
/// on *Connecting* for the life of the process, which reads exactly like a probe that never
/// finishes.
///
/// **A publication in the app's own Documents folder belonged to nobody.** `source(of:)`
/// matched a folder to a source by locator, and the Documents folder is not a source the
/// reader added, so every publication that arrived through Files, AirDrop or Open-in was
/// attributed to `nil`. Unattributed rows are invisible to Settings, so the per-source counts
/// could not add up to the shelf and no screen could say where the shelf came from. They are
/// filed under "On this device" now — the source that already means *in storage the app
/// owns*, which is what the Documents folder is.
@Suite("A local library states what it is and what it holds")
@MainActor
struct LocalSourceStateTests {

    private func temporaryFolder() throws -> URL {
        let root = URL.temporaryDirectory.appending(path: "local-state-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    // MARK: - The state a folder reports

    @Test("A folder that is there is connected, not connecting")
    func presentFolderIsConnected() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let model = LibraryModel()
        model.folders = [folder]
        model.registry = SourceRegistry(sources: [
            Source(
                displayName: folder.lastPathComponent,
                kind: .localFolder,
                state: .connecting,
                locator: folder.lastPathComponent
            )
        ])

        model.resolveLocalSources()
        #expect(model.registry.sources.first?.state == .connected)
    }

    /// The sweep's folder, and the reason it sat on *Connecting*.
    ///
    /// A bookmark that did not restore leaves no URL in `folders`, so there is nothing to
    /// stat — which is the same answer as a folder that is no longer readable, and `sources`
    /// wants that answer grey rather than red.
    @Test("A folder whose bookmark did not restore is unreachable, not connecting")
    func unrestoredFolderIsUnreachable() {
        let model = LibraryModel()
        model.registry = SourceRegistry(sources: [
            Source(
                displayName: "Comics on this iPhone",
                kind: .localFolder,
                state: .connecting,
                locator: "Comics on this iPhone"
            )
        ])

        model.resolveLocalSources()
        let state = model.registry.sources.first?.state
        guard case .unreachable = state else {
            Issue.record("A folder with no restored URL still reads \(String(describing: state)).")
            return
        }
    }

    /// "No answer since …" must say when it stopped answering, not when it was last asked.
    @Test("An already-unreachable folder keeps the moment it went")
    func unreachableFolderKeepsItsDate() {
        let wentAt = Date(timeIntervalSince1970: 1_000_000)
        let model = LibraryModel()
        model.registry = SourceRegistry(sources: [
            Source(displayName: "Attic", kind: .localFolder, state: .unreachable(since: wentAt), locator: "Attic")
        ])

        model.resolveLocalSources()
        #expect(model.registry.sources.first?.state == .unreachable(since: wentAt))
    }

    /// "On this device" is app storage. It exists only while something is filed under it, so
    /// its existence is its reachability — there is no folder to stat and no network to ask.
    @Test("On this device is connected, never connecting")
    func localStorageSourceIsConnected() {
        let model = LibraryModel()
        model.registry = SourceRegistry(sources: [
            Source(
                id: ImportedCopies.sourceID,
                displayName: "On this device",
                kind: .localFolder,
                state: .connecting,
                locator: LibraryModel.importedLocator
            )
        ])

        model.resolveLocalSources()
        #expect(model.registry.sources.first?.state == .connected)
    }

    /// The network's own question is not answered here, and must not be guessed at.
    @Test("A network source is left alone")
    func networkSourcesAreUntouched() {
        let model = LibraryModel()
        model.registry = SourceRegistry(sources: [
            Source(displayName: "Attic NAS", kind: .networkShare, state: .connecting),
            Source(displayName: "Test Catalogue", kind: .opdsCatalog, state: .connecting),
            Source(displayName: "ada", kind: .kavitaServer, state: .connecting)
        ])

        model.resolveLocalSources()
        #expect(model.registry.sources.allSatisfy { $0.state == .connecting })
    }

    // MARK: - What a source is credited with

    @Test("A publication in the app's own Documents folder is attributed, not orphaned")
    func documentsFolderIsASource() throws {
        let documents = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: documents) }

        let model = LibraryModel(documents: documents)
        #expect(model.source(of: documents) == ImportedCopies.sourceID)
    }

    /// A folder the reader picked keeps its own identity, whatever it is called.
    @Test("A picked folder is still matched by its locator")
    func pickedFolderKeepsItsOwnSource() throws {
        let documents = try temporaryFolder()
        let picked = try temporaryFolder()
        defer {
            try? FileManager.default.removeItem(at: documents)
            try? FileManager.default.removeItem(at: picked)
        }

        let source = Source(
            displayName: "Comics",
            kind: .localFolder,
            state: .connected,
            locator: picked.lastPathComponent
        )
        let model = LibraryModel(documents: documents)
        model.registry = SourceRegistry(sources: [source])

        #expect(model.source(of: picked) == source.id)
        #expect(model.source(of: documents) == ImportedCopies.sourceID)
    }

    /// An unregistered folder is still nobody's, which is the honest answer.
    @Test("A folder that is neither picked nor the app's own is unattributed")
    func strangerFolderIsUnattributed() throws {
        let documents = try temporaryFolder()
        let stranger = try temporaryFolder()
        defer {
            try? FileManager.default.removeItem(at: documents)
            try? FileManager.default.removeItem(at: stranger)
        }

        let model = LibraryModel(documents: documents)
        #expect(model.source(of: stranger) == nil)
    }

    /// The count the source screen shows is the one the shelf can account for.
    @Test("The counts add up to the shelf")
    func countsAccountForTheShelf() throws {
        let documents = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: documents) }

        let model = LibraryModel(documents: documents)
        let picked = Source(displayName: "Comics", kind: .localFolder, state: .connected, locator: "Comics")
        model.registry = SourceRegistry(sources: [picked])

        model.adopt(publication("a"), from: model.source(of: documents))
        model.adopt(publication("b"), from: model.source(of: documents))
        model.adopt(publication("c"), from: picked.id)

        #expect(model.itemCount(of: ImportedCopies.sourceID) == 2)
        #expect(model.itemCount(of: picked.id) == 1)
        let accounted = model.registry.sources.reduce(0) { $0 + model.itemCount(of: $1.id) }
            + model.itemCount(of: ImportedCopies.sourceID)
        #expect(accounted >= model.publications.count)
        #expect(model.publications.allSatisfy { $0.sourceID != nil })
    }

    private func publication(_ name: String) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/tmp/\(name).cbz"),
            format: .cbz,
            displayTitle: name,
            origin: .inferred
        )
    }
}
