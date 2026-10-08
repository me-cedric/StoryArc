import Foundation
import Synchronization
import Testing

import StoryArcCore
@testable import Persistence

/// A secure store in memory.
final class MemorySecrets: SourceSecretStore {
    private let held = Mutex<[String: String]>([:])

    var contents: [String: String] { held.withLock { $0 } }

    func save(_ secret: String, for reference: String) -> Bool {
        held.withLock { $0[reference] = secret }
        return true
    }

    func secret(for reference: String) -> String? { held.withLock { $0[reference] } }

    func remove(_ reference: String) -> Bool {
        held.withLock { _ = $0.removeValue(forKey: reference) }
        return true
    }
}

/// A progress ledger that refuses every save.
private actor RefusingLedger: ProgressLedger {
    struct Refused: Error {}

    private let inner: ProgressStore

    init(_ inner: ProgressStore) { self.inner = inner }

    func recent(limit: Int) async throws -> [ReadingProgress] { try await inner.recent(limit: limit) }
    func save(_ progress: ReadingProgress) async throws { throw Refused() }
    func mark(_ identity: PublicationIdentity, finished: Bool, at: Date) async throws {
        try await inner.mark(identity, finished: finished, at: at)
    }
    func forget(_ identity: PublicationIdentity) async throws { try await inner.forget(identity) }
}

/// One device: real stores in a suite of their own, and a secure store in memory.
private struct Rig {
    let archive: LibraryArchive
    let secrets = MemorySecrets()
    let transfer: LibraryTransfer

    init(ledger: (any ProgressLedger)? = nil) throws {
        let defaults = UserDefaults(suiteName: "app.storyarc.tests.\(UUID().uuidString)") ?? .standard
        archive = LibraryArchive(defaults: defaults, progress: try ledger ?? ProgressStore.inMemory())
        transfer = LibraryTransfer(archive: archive, secrets: secrets)
    }
}

/// `library-portability` tasks 2.5, 3.1, 5.3 and 5.4 against real stores: the document leaves as
/// bytes, and comes back as a plan, and only a confirmed import changes the device. Android's
/// `LibraryTransferTest` asserts the same rows.
@Suite("A library transfer moves the stores and the secrets, or nothing")
struct LibraryTransferTests {

    private static let shareID = UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID()
    private static let kavitaID = UUID(uuidString: "55555555-5555-5555-5555-555555555555") ?? UUID()
    private static let appVersion = "10.14.0"

    private struct Vector: Decodable {
        let passphrase: String
        let plaintexts: [String: String]
        let secrets: LibrarySecrets
    }

    /// The vector the two platforms and a third implementation all open, found by walking up.
    private func vector() throws -> Vector {
        var directory = URL(filePath: #filePath)
        while directory.pathComponents.count > 1 {
            directory.deleteLastPathComponent()
            let file = directory.appending(path: "packages/test-fixtures/library/sealed-secrets.json")
            if let data = try? Data(contentsOf: file) {
                return try JSONDecoder().decode(Vector.self, from: data)
            }
        }
        throw CocoaError(.fileNoSuchFile)
    }

    private func text(_ bytes: Data) -> String { String(bytes: bytes, encoding: .utf8) ?? "" }

    /// The library an export carries, sources only: a share and a server, each holding a secret.
    private func sourceLibrary(handle: (String) -> String) -> LibrarySnapshot {
        LibrarySnapshot(
            sources: SourceRegistry(sources: [
                Source(
                    id: Self.shareID,
                    displayName: "Comics NAS",
                    kind: .networkShare,
                    credentialReference: handle("share"),
                    locator: "smb://reader@nas.local/comics"
                ),
                Source(
                    id: Self.kavitaID,
                    displayName: "Kavita",
                    kind: .kavitaServer,
                    credentialReference: handle("kavita"),
                    locator: "https://kavita.example/api?library=3"
                ),
            ]),
            certificatePins: ["nas.local": ["AB:CD"]]
        )
    }

    /// This device holding the library, with its two secrets in the secure store.
    private func seeded(_ rig: Rig) async throws {
        _ = rig.secrets.save("nas-password", for: "share-handle")
        _ = rig.secrets.save("kavita-key", for: "kavita-handle")
        var library = sourceLibrary { "\($0)-handle" }
        library.shelves = Shelves(collections: [PublicationCollection(name: "Image Comics", members: ["path:/a.cbz"])])
        try await rig.archive.apply(library)
    }

    /// The bytes another device would hand over, sealed by the committed vector or not.
    private func documentBytes(from library: LibrarySnapshot, sealed: Bool = false) throws -> Data {
        let document = LibraryExport.document(
            library,
            appVersion: Self.appVersion,
            writtenAt: Date(timeIntervalSince1970: 1_767_225_845),
            secrets: sealed ? try vector().secrets : nil
        )
        return try LibraryDocumentCoder.encode(document)
    }

    private func incoming(sealed: Bool = true) throws -> Data {
        try documentBytes(from: sourceLibrary { _ in "elsewhere" }, sealed: sealed)
    }

    // MARK: Export

    @Test("An export with the switch off writes no secrets object, though the store holds secrets")
    func exportWithoutPasswords() async throws {
        let rig = try Rig()
        try await seeded(rig)

        let bytes = try await rig.transfer.exportData(appVersion: Self.appVersion)

        #expect(!text(bytes).contains("\"secrets\""))
        #expect(!text(bytes).contains("nas-password"))
        #expect(!text(bytes).contains("kavita-key"))
        #expect(try LibraryDocumentCoder.decode(bytes).secrets == nil)
    }

    @Test("An export with the switch on seals each stored secret and writes none in clear")
    func exportWithPasswords() async throws {
        let rig = try Rig()
        try await seeded(rig)

        let bytes = try await rig.transfer.exportData(appVersion: Self.appVersion, passphrase: "a long phrase")
        let block = try #require(try LibraryDocumentCoder.decode(bytes).secrets)

        #expect(!text(bytes).contains("nas-password"))
        #expect(!text(bytes).contains("kavita-key"))
        #expect(!text(bytes).contains("a long phrase"))
        #expect(
            try LibrarySecretSealer.open(block, passphrase: "a long phrase")
                == [Self.shareID: "nas-password", Self.kavitaID: "kavita-key"]
        )
    }

    @Test("The exported bytes decode back to the library they were written from")
    func exportRoundTrips() async throws {
        let rig = try Rig()
        try await seeded(rig)
        let snapshot = try await rig.archive.snapshot()

        let document = try LibraryDocumentCoder.decode(
            try await rig.transfer.exportData(appVersion: Self.appVersion)
        )

        #expect(document.library == LibraryExport.document(
            snapshot, appVersion: Self.appVersion, writtenAt: document.writtenAt
        ).library)
    }

    // MARK: Preview

    @Test("A preview states what will happen and changes nothing")
    func previewChangesNothing() async throws {
        let rig = try Rig()
        let before = try await rig.archive.snapshot()

        let preview = try await rig.transfer.preview(try incoming())

        #expect(preview.plan.sourcesToAdd == ["Comics NAS", "Kavita"])
        #expect(preview.plan.certificatePinsToAdd.map(\.host) == ["nas.local"])
        #expect(preview.needsPassphrase)
        #expect(try await rig.archive.snapshot() == before)
        #expect(rig.secrets.contents.isEmpty)
    }

    @Test("A newer document is refused by name and the device is unchanged")
    func aNewerDocumentIsRefused() async throws {
        let rig = try Rig()
        let before = try await rig.archive.snapshot()
        let newer = text(try incoming(sealed: false)).replacing("\"formatVersion\" : 1", with: "\"formatVersion\" : 7")

        await #expect(throws: LibraryDocumentFailure.newerThanThisApp(found: 7, understood: 1)) {
            try await rig.transfer.preview(Data(newer.utf8))
        }
        #expect(try await rig.archive.snapshot() == before)
        #expect(rig.secrets.contents.isEmpty)
    }

    // MARK: Import

    @Test("The right passphrase writes each secret to the store and signs the sources in")
    func importWithTheRightPassphrase() async throws {
        let rig = try Rig()
        let preview = try await rig.transfer.preview(try incoming())

        let outcome = try await rig.transfer.performImport(preview, passphrase: try vector().passphrase)

        #expect(outcome.secretsWritten == 2)
        #expect(outcome.sourcesNeedingSignIn.isEmpty)
        #expect(rig.secrets.contents == [
            CredentialStore.reference(for: Self.shareID): "nas-password-é世",
            CredentialStore.reference(for: Self.kavitaID): "kavita-api-key-0123456789abcdef",
        ])
        let held = try await rig.archive.snapshot()
        #expect(held.sources.sources.allSatisfy { $0.credentialReference == CredentialStore.reference(for: $0.id) })
        #expect(held.certificatePins == ["nas.local": ["AB:CD"]])
    }

    @Test("A wrong passphrase is refused before anything is written, and may be tried again")
    func aWrongPassphrase() async throws {
        let rig = try Rig()
        let before = try await rig.archive.snapshot()
        let preview = try await rig.transfer.preview(try incoming())

        await #expect(throws: LibraryImportFailure.passphraseRefused) {
            try await rig.transfer.performImport(preview, passphrase: "not it")
        }
        #expect(try await rig.archive.snapshot() == before)
        #expect(rig.secrets.contents.isEmpty)

        let retry = try await rig.transfer.performImport(preview, passphrase: try vector().passphrase)
        #expect(retry.secretsWritten == 2)
    }

    @Test("Skipping imports the rest and lists each source as needing a sign-in")
    func skippingTheSecrets() async throws {
        let rig = try Rig()
        let preview = try await rig.transfer.preview(try incoming())

        let outcome = try await rig.transfer.performImport(preview, passphrase: nil)

        #expect(outcome.secretsWritten == 0)
        #expect(outcome.sourcesNeedingSignIn == ["Comics NAS", "Kavita"])
        #expect(rig.secrets.contents.isEmpty)
        let held = try await rig.archive.snapshot().sources.sources
        #expect(held.map(\.displayName) == ["Comics NAS", "Kavita"])
        #expect(held.allSatisfy { $0.credentialReference == nil })
    }

    @Test("A write that fails after the secrets were stored takes the secrets back out")
    func aFailedImportLeavesNoSecrets() async throws {
        let rig = try Rig(ledger: RefusingLedger(try ProgressStore.inMemory()))
        let before = try await rig.archive.snapshot()
        var library = sourceLibrary { _ in "elsewhere" }
        library.progress = [
            ReadingProgress(
                identity: PublicationIdentity(contentDigest: "d1"),
                position: .page(index: 3, of: 20),
                updatedAt: Date(timeIntervalSince1970: 1_767_100_000)
            ),
        ]
        let preview = try await rig.transfer.preview(try documentBytes(from: library, sealed: true))

        await #expect(throws: RefusingLedger.Refused.self) {
            try await rig.transfer.performImport(preview, passphrase: try vector().passphrase)
        }
        #expect(try await rig.archive.snapshot() == before)
        #expect(rig.secrets.contents.isEmpty)
    }

    @Test("A document sealed by another implementation opens here: the shared vector")
    func theSharedVector() async throws {
        let vector = try vector()
        let rig = try Rig()
        let preview = try await rig.transfer.preview(try incoming())

        _ = try await rig.transfer.performImport(preview, passphrase: vector.passphrase)

        let expected = Dictionary(uniqueKeysWithValues: vector.plaintexts.map {
            (CredentialStore.reference(for: UUID(uuidString: $0.key) ?? UUID()), $0.value)
        })
        #expect(rig.secrets.contents == expected)
    }
}
