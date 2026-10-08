import Foundation
import Testing

@testable import StoryArcCore

/// `library-portability` task 5.4: which sources an import gives a secret to, and what the merge
/// does with one it opened. Android's `LibraryImportSecretsTest` asserts the same rows.
///
/// The document is sealed by the committed vector, which a third implementation made, so the
/// block here is what the other platform's export would hold.
@Suite("An import gives an opened secret to the sources that lack one")
struct LibraryImportSecretsTests {

    private struct Vector: Decodable {
        let passphrase: String
        let plaintexts: [String: String]
        let secrets: LibrarySecrets
    }

    private func vector() throws -> Vector {
        try JSONDecoder().decode(
            Vector.self,
            from: LibraryDocumentFixture.document(named: "sealed-secrets.json")
        )
    }

    private func sealedDocument() throws -> LibraryDocument {
        LibraryExport.document(
            LibraryDocumentFixture.snapshot,
            appVersion: LibraryDocumentFixture.appVersion,
            writtenAt: LibraryDocumentFixture.writtenAt,
            secrets: try vector().secrets
        )
    }

    private func opened() throws -> [UUID: String] {
        let vector = try vector()
        return try LibrarySecretSealer.open(vector.secrets, passphrase: vector.passphrase)
    }

    private let empty = LibrarySnapshot()

    @Test("A document with sealed secrets for sources it brings needs a passphrase")
    func needsAPassphrase() throws {
        let document = try sealedDocument()

        #expect(LibraryImport.needsPassphrase(document, onto: empty))
        #expect(LibraryImport.fillableSources(document, onto: empty)
            == [LibraryDocumentFixture.networkShareID, LibraryDocumentFixture.kavitaID])
    }

    @Test("A document with no secrets asks for nothing")
    func noSecretsNoPassphrase() throws {
        let plain = LibraryExport.document(
            LibraryDocumentFixture.snapshot,
            appVersion: LibraryDocumentFixture.appVersion,
            writtenAt: LibraryDocumentFixture.writtenAt
        )

        #expect(!LibraryImport.needsPassphrase(plain, onto: empty))
    }

    @Test("A source this device is already signed in to keeps its own secret")
    func aSignedInSourceIsLeftAlone() throws {
        var device = empty
        device.sources = SourceRegistry(sources: [
            Source(
                id: LibraryDocumentFixture.networkShareID,
                displayName: "Comics NAS",
                kind: .networkShare,
                credentialReference: "mine"
            ),
        ])

        let document = try sealedDocument()
        let result = LibraryImport.merging(
            document, into: device, secrets: try opened(), reference: { $0.uuidString }
        )

        #expect(LibraryImport.fillableSources(document, onto: device) == [LibraryDocumentFixture.kavitaID])
        #expect(result.credentialed == [LibraryDocumentFixture.kavitaID])
        let held = result.snapshot.sources.sources.first { $0.id == LibraryDocumentFixture.networkShareID }
        #expect(held?.credentialReference == "mine")
    }

    @Test("A source the device holds with no secret is given the one the document carries")
    func aHeldSourceWithoutASecretIsFilled() throws {
        var device = empty
        device.sources = SourceRegistry(sources: [
            Source(id: LibraryDocumentFixture.kavitaID, displayName: "My Kavita", kind: .kavitaServer),
        ])

        let result = LibraryImport.merging(
            try sealedDocument(), into: device, secrets: try opened(), reference: { "ref:\($0.uuidString)" }
        )
        let kavita = result.snapshot.sources.sources.first { $0.id == LibraryDocumentFixture.kavitaID }

        #expect(kavita?.credentialReference == "ref:\(LibraryDocumentFixture.kavitaID.uuidString)")
        // The device's own name for it stands.
        #expect(kavita?.displayName == "My Kavita")
    }

    @Test("A source given a secret gets its handle and is no longer listed as needing a sign-in")
    func aFilledSourceIsSignedIn() throws {
        let result = LibraryImport.merging(
            try sealedDocument(), into: empty, secrets: try opened(), reference: { $0.uuidString }
        )
        let share = result.snapshot.sources.sources.first { $0.id == LibraryDocumentFixture.networkShareID }

        #expect(share?.credentialReference == LibraryDocumentFixture.networkShareID.uuidString)
        #expect(result.credentialed == [LibraryDocumentFixture.networkShareID, LibraryDocumentFixture.kavitaID])
        #expect(result.sourcesNeedingSignIn.isEmpty)
    }

    @Test("Without opened secrets every source that held one asks for a sign-in")
    func skippingLeavesTheSignIns() throws {
        let result = LibraryImport.merging(
            try sealedDocument(), into: empty, secrets: [:], reference: { $0.uuidString }
        )

        #expect(result.credentialed.isEmpty)
        #expect(result.sourcesNeedingSignIn == ["Comics NAS", "Kavita"])
        #expect(result.snapshot.sources.sources.allSatisfy { $0.credentialReference == nil })
    }

    @Test("A secret for a source the document does not carry is ignored")
    func aStraySecretIsIgnored() throws {
        let stranger = LibraryDocumentFixture.fixed("99999999-9999-9999-9999-999999999999")

        let result = LibraryImport.merging(
            try sealedDocument(), into: empty, secrets: [stranger: "x"], reference: { $0.uuidString }
        )

        #expect(result.credentialed.isEmpty)
    }
}
