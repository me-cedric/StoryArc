import Catalogue
import Foundation
import Kavita
import SwiftUI
import Testing

@testable import LibraryFeature
import Persistence
import StoryArcCore

/// `library-portability` task 3.4: an imported source asks for its secret when it is reached.
///
/// The import half is asserted in `LibraryImportTests`: the source arrives with no secret and is
/// named in `sourcesNeedingSignIn`. This is the other half. A source that came through an import
/// is asked by the same probe as any other, lands in the unauthorised state with no request made
/// (it holds nothing to send), offers the one action that asks for the secret, and shows the
/// explanation instead of a browser that would fail. Everything else in the library stays where
/// it was. Android's `ImportedSourceSignInTest` asserts the same rows.
@Suite("An imported source asks for its secret when it is reached")
@MainActor
struct ImportedSourceSignInTests {

    private let kavitaID = UUID(uuidString: "55555555-5555-5555-5555-555555555555") ?? UUID()

    /// A document that carries one Kavita server the writing device was signed in to.
    private var document: LibraryDocument {
        LibraryExport.document(
            LibrarySnapshot(sources: SourceRegistry(sources: [
                Source(
                    id: kavitaID,
                    displayName: "Kavita",
                    kind: .kavitaServer,
                    credentialReference: "elsewhere",
                    locator: "https://kavita.invalid/api?library=3"
                ),
            ])),
            appVersion: "10.14.0",
            writtenAt: Date(timeIntervalSince1970: 1_767_225_845)
        )
    }

    /// A device holding a folder with one publication, and then the import of the document above.
    private func importedLibrary() throws -> (model: LibraryModel, publication: Publication) {
        let folder = Source(displayName: "Shelf", kind: .localFolder, state: .connected, locator: "/Books/Shelf")
        let device = LibrarySnapshot(sources: SourceRegistry(sources: [folder]))
        let merged = LibraryImport.merging(document, into: device).snapshot

        let defaults = try #require(UserDefaults(suiteName: "app.storyarc.tests.\(UUID().uuidString)"))
        let store = SourceStore(defaults: defaults)
        store.save(merged.sources)
        let publication = Publication(
            identity: PublicationIdentity(normalizedPath: "/Books/Shelf/a.cbz"),
            format: .cbz,
            displayTitle: "Already here",
            origin: .inferred,
            sourceID: folder.id
        )
        let model = LibraryModel(sourceStore: store)
        model.publications = [publication]
        model.rebuild()
        return (model, publication)
    }

    private var credentials: CredentialStore {
        CredentialStore(service: "app.storyarc.tests.\(UUID().uuidString)")
    }

    private func imported(_ model: LibraryModel) throws -> Source {
        try #require(model.registry.sources.first { $0.id == kavitaID })
    }

    @Test("The imported source holds no secret, so the probe lands it in the unauthorised state")
    func theProbeLandsItUnauthorised() async throws {
        let (model, _) = try importedLibrary()
        let arrived = try imported(model)
        #expect(arrived.credentialReference == nil)

        await model.resolveSources(credentials: credentials, pins: CertificatePins())

        let state = try imported(model).state
        guard case .unauthorized = state else {
            Issue.record("expected unauthorised, got \(state)")
            return
        }
    }

    @Test("It offers the action that asks for the secret, first")
    func theFirstActionAsksForTheSecret() async throws {
        let (model, _) = try importedLibrary()
        await model.resolveSources(credentials: credentials, pins: CertificatePins())

        let diagnosis = SourceDiagnosis.of(try imported(model), itemCount: 0, downloads: [])

        #expect(diagnosis.actions.first == .reconnect)
    }

    @Test("The library it joined stays browsable")
    func theLibraryStaysBrowsable() async throws {
        let (model, publication) = try importedLibrary()

        await model.resolveSources(credentials: credentials, pins: CertificatePins())

        #expect(model.visible.map(\.id) == [publication.id])
    }

    @Test("Opening it shows the sign-in explanation instead of a browser, and says nobody stored one")
    func openingItExplains() async throws {
        let (model, _) = try importedLibrary()
        await model.resolveSources(credentials: credentials, pins: CertificatePins())
        let source = try imported(model)
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))

        let browser = SourceBrowser(
            source: source,
            model: model,
            pins: CertificatePins(),
            credentials: credentials,
            kavitaProgress: KavitaProgressStore(defaults: defaults),
            lists: [],
            onOpen: { _, _ in }
        )
        let explanations = visited(in: browser).compactMap { $0 as? UnreachableSource }

        // Found as itself and as what wraps it, so it is counted, not equal.
        #expect(!explanations.isEmpty)
        #expect(explanations.allSatisfy { !$0.isRefused && $0.name == "Kavita" })
    }

    @Test("A source that holds a secret the server refused is told it was refused")
    func aRefusedSecretIsTold() throws {
        let source = Source(
            displayName: "Kavita",
            kind: .kavitaServer,
            state: .unauthorized(reason: "refused"),
            credentialReference: "held",
            locator: "https://kavita.invalid/api"
        )
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))

        let browser = SourceBrowser(
            source: source,
            model: LibraryModel(),
            pins: CertificatePins(),
            credentials: credentials,
            kavitaProgress: KavitaProgressStore(defaults: defaults),
            lists: [],
            onOpen: { _, _ in }
        )

        let explanations = visited(in: browser).compactMap { $0 as? UnreachableSource }
        #expect(!explanations.isEmpty)
        #expect(explanations.allSatisfy { $0.isRefused })
    }

    /// Every value a view holds, found by walking the view's own value.
    private func visited(in view: some View) -> [Any] {
        var found: [Any] = []
        func walk(_ value: Any, depth: Int) {
            guard depth < 40 else { return }
            found.append(value)
            for child in Mirror(reflecting: value).children { walk(child.value, depth: depth + 1) }
        }
        walk(view.body, depth: 0)
        return found
    }
}
