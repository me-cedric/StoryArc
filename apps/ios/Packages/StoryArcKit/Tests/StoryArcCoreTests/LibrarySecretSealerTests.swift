import Foundation
import Testing

@testable import StoryArcCore

/// `library-portability` task 5.2: a secret sealed under a passphrase, and opened again.
///
/// `packages/test-fixtures/library/sealed-secrets.json` is one vector, sealed once by a third
/// implementation (Python's `cryptography`, not either app). Both platforms' suites open it, and
/// both seal the same inputs to the same bytes, so the two cannot drift. Android's
/// `LibrarySecretSealerTest` asserts the same rows.
@Suite("A secret sealed under a passphrase opens only under that passphrase")
struct LibrarySecretSealerTests {

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

    private func plaintexts(_ vector: Vector) -> [UUID: String] {
        Dictionary(
            uniqueKeysWithValues: vector.plaintexts.map { (LibraryDocumentFixture.fixed($0.key), $0.value) }
        )
    }

    private func flipped(_ base64: String, at index: Int) throws -> String {
        var bytes = try #require(Data(base64Encoded: base64))
        bytes[index] ^= 0x01
        return bytes.base64EncodedString()
    }

    @Test("The committed vector opens under its passphrase, on this platform")
    func theCommittedVectorOpens() throws {
        let vector = try vector()

        let opened = try LibrarySecretSealer.open(vector.secrets, passphrase: vector.passphrase)

        #expect(opened == plaintexts(vector))
    }

    @Test("The same passphrase typed in decomposed form opens it too")
    func theSpellingOfThePassphraseDoesNotMatter() throws {
        let vector = try vector()
        let decomposed = vector.passphrase.decomposedStringWithCanonicalMapping
        try #require(decomposed.unicodeScalars.count != vector.passphrase.unicodeScalars.count)

        #expect(try LibrarySecretSealer.open(vector.secrets, passphrase: decomposed)
            == plaintexts(vector))
    }

    @Test("This platform seals the vector's inputs to the vector's own bytes")
    func sealingMatchesTheCommittedVector() throws {
        let vector = try vector()
        let ids = plaintexts(vector).keys.sorted { $0.uuidString < $1.uuidString }
        let nonces = Dictionary(uniqueKeysWithValues: try ids.enumerated().map { offset, id in
            (id, Data((0..<12).map { UInt8(0x20 + offset * 0x10 + $0) }))
        })

        let sealed = try LibrarySecretSealer.seal(
            plaintexts(vector),
            passphrase: vector.passphrase,
            salt: Data((0..<16).map { UInt8($0) }),
            nonces: nonces
        )

        #expect(sealed == vector.secrets)
    }

    @Test("A wrong passphrase opens nothing")
    func aWrongPassphrase() throws {
        let vector = try vector()

        #expect(throws: LibrarySecretsFailure.wrongPassphraseOrDamaged) {
            try LibrarySecretSealer.open(vector.secrets, passphrase: "not the passphrase")
        }
    }

    @Test("A changed byte in the ciphertext, in its tag or in its nonce opens nothing")
    func tamperedBytes() throws {
        let vector = try vector()
        let key = try #require(vector.secrets.sealed.keys.sorted().first)
        let entry = try #require(vector.secrets.sealed[key])

        let changes = [
            SealedSecret(nonce: entry.nonce, ciphertext: try flipped(entry.ciphertext, at: 0)),
            SealedSecret(nonce: entry.nonce, ciphertext: try flipped(entry.ciphertext, at: 20)),
            SealedSecret(nonce: try flipped(entry.nonce, at: 0), ciphertext: entry.ciphertext),
        ]
        for change in changes {
            var damaged = vector.secrets
            damaged.sealed[key] = change
            #expect(throws: LibrarySecretsFailure.wrongPassphraseOrDamaged) {
                try LibrarySecretSealer.open(damaged, passphrase: vector.passphrase)
            }
        }
    }

    @Test("A fresh seal opens again, with a salt and a nonce of its own each time")
    func aFreshSealRoundTrips() throws {
        let secrets = [LibraryDocumentFixture.networkShareID: "correct horse"]

        let first = try LibrarySecretSealer.seal(secrets, passphrase: "battery staple")
        let second = try LibrarySecretSealer.seal(secrets, passphrase: "battery staple")

        #expect(try LibrarySecretSealer.open(first, passphrase: "battery staple") == secrets)
        #expect(first.salt != second.salt)
        #expect(first.sealed.values.map(\.nonce) != second.sealed.values.map(\.nonce))
        #expect(first.iterations >= 600_000)
        #expect(first.kdf == "PBKDF2-HMAC-SHA256")
        #expect(first.cipher == "AES-256-GCM")
    }

    @Test("A source is keyed by its id in lower case, so both platforms name it alike")
    func theKeyIsLowerCase() throws {
        let id = LibraryDocumentFixture.fixed("ABCDEFAB-CDEF-ABCD-EFAB-CDEFABCDEFAB")

        let sealed = try LibrarySecretSealer.seal([id: "x"], passphrase: "battery staple")

        #expect(sealed.sealed.keys.sorted() == ["abcdefab-cdef-abcd-efab-cdefabcdefab"])
        #expect(try LibrarySecretSealer.open(sealed, passphrase: "battery staple") == [id: "x"])
    }

    @Test("A block this build does not read is refused by name")
    func anUnsupportedBlock() throws {
        let vector = try vector()
        var changes: [LibrarySecrets] = []
        for mutate in [
            { (secrets: inout LibrarySecrets) in secrets.kdf = "scrypt" },
            { (secrets: inout LibrarySecrets) in secrets.cipher = "ChaCha20-Poly1305" },
            { (secrets: inout LibrarySecrets) in secrets.iterations = 0 },
            { (secrets: inout LibrarySecrets) in
                secrets.iterations = LibrarySecretSealer.maximumIterations + 1
            },
        ] {
            var changed = vector.secrets
            mutate(&changed)
            changes.append(changed)
        }
        for changed in changes {
            #expect(throws: LibrarySecretsFailure.unsupported) {
                try LibrarySecretSealer.open(changed, passphrase: vector.passphrase)
            }
        }
    }

    @Test("A nonce of the wrong length is malformed, not a wrong passphrase")
    func aMalformedNonce() throws {
        let vector = try vector()
        let key = try #require(vector.secrets.sealed.keys.first)
        var damaged = vector.secrets
        damaged.sealed[key]?.nonce = Data([1, 2, 3]).base64EncodedString()

        #expect(throws: LibrarySecretsFailure.malformed) {
            try LibrarySecretSealer.open(damaged, passphrase: vector.passphrase)
        }
    }

    @Test("No passphrase is not a passphrase")
    func anEmptyPassphrase() {
        #expect(throws: LibrarySecretsFailure.emptyPassphrase) {
            try LibrarySecretSealer.seal([LibraryDocumentFixture.kavitaID: "x"], passphrase: "")
        }
    }

    @Test("A document carries the sealed block, and the secret is in none of its bytes")
    func theDocumentCarriesOnlyCiphertext() throws {
        let secret = "a-secret-nobody-may-read-7c1f"
        let sealed = try LibrarySecretSealer.seal(
            [LibraryDocumentFixture.networkShareID: secret],
            passphrase: "battery staple"
        )
        let document = LibraryExport.document(
            LibraryDocumentFixture.snapshot,
            appVersion: LibraryDocumentFixture.appVersion,
            writtenAt: LibraryDocumentFixture.writtenAt,
            secrets: sealed
        )

        let bytes = try LibraryDocumentCoder.encode(document)
        let read = try LibraryDocumentCoder.decode(bytes)

        let text = String(bytes: bytes, encoding: .utf8) ?? ""
        #expect(!text.contains(secret))
        #expect(!text.contains("battery staple"))
        #expect(read.secrets == sealed)
        #expect(try LibrarySecretSealer.open(try #require(read.secrets), passphrase: "battery staple")
            == [LibraryDocumentFixture.networkShareID: secret])
    }
}
