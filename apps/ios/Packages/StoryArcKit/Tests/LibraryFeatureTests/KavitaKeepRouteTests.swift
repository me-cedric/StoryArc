import Foundation
import Persistence
import StoryArcCore
import Testing

@testable import LibraryFeature

/// Whether a Kavita library row the reader has only ever seen on a shelf — never opened,
/// never kept — can still become a download.
///
/// `kavita-server` task 12.5: `DetailActions` drew a Download control for exactly this row,
/// and the tap did nothing. `LibraryModel.canKeepKavitaChapter(_:origin:)` is the route this
/// proves, with a fake `origin` resolver so the claim needs neither `UserDefaults.standard`
/// nor a network — `KavitaContributorCatalogOriginTests` already proves the resolver itself.
@MainActor
@Suite("Whether a browsed Kavita chapter can still be kept")
struct KavitaKeepRouteTests {

    private let sourceID = UUID()

    private func publication(remoteID: String = "chapter:3103") -> Publication {
        Publication(
            identity: PublicationIdentity(
                serverIdentifier: .init(sourceID: sourceID, remoteID: remoteID)
            ),
            format: .cbz,
            displayTitle: "Issue #43",
            origin: .authoritative
        )
    }

    private func origin() -> KavitaOrigin {
        KavitaOrigin(
            sourceId: sourceID.uuidString,
            libraryId: 7,
            seriesId: 312,
            volumeId: 55,
            chapterId: 3103
        )
    }

    /// A model whose registry holds one reachable Kavita source, named `sourceID`.
    private func modelWithReachableSource() throws -> (LibraryModel, CredentialStore) {
        let credentials = CredentialStore(service: "app.storyarc.tests.\(UUID().uuidString)")
        let reference = CredentialStore.reference(for: sourceID)
        #expect(credentials.save("api-key", for: reference))
        let source = Source(
            id: sourceID,
            displayName: "Attic",
            kind: .kavitaServer,
            credentialReference: reference,
            locator: "https://kavita.example"
        )
        let model = LibraryModel()
        model.registry = SourceRegistry(sources: [source])
        return (model, credentials)
    }

    @Test("A chapter row with a resolvable origin and a reachable source has a route")
    func routeExistsWithOriginAndSource() throws {
        let (model, credentials) = try modelWithReachableSource()
        defer { credentials.remove(CredentialStore.reference(for: sourceID)) }

        #expect(
            model.canKeepKavitaChapter(publication(), origin: { _ in self.origin() }, credentials: credentials)
        )
    }

    @Test("No route without an origin, even with a reachable source")
    func noRouteWithoutOrigin() throws {
        let (model, credentials) = try modelWithReachableSource()
        defer { credentials.remove(CredentialStore.reference(for: sourceID)) }

        #expect(!model.canKeepKavitaChapter(publication(), origin: { _ in nil }, credentials: credentials))
    }

    @Test("No route without a registered source, even with an origin")
    func noRouteWithoutSource() {
        let model = LibraryModel()
        model.registry = SourceRegistry(sources: [])

        #expect(!model.canKeepKavitaChapter(publication(), origin: { _ in self.origin() }, credentials: nil))
    }

    @Test("A row that is not a Kavita chapter at all has no route")
    func noRouteForNonKavitaRow() throws {
        let (model, credentials) = try modelWithReachableSource()
        defer { credentials.remove(CredentialStore.reference(for: sourceID)) }

        #expect(
            !model.canKeepKavitaChapter(
                publication(remoteID: "opds:9"), origin: { _ in self.origin() }, credentials: credentials
            )
        )
    }
}
