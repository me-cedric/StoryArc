import Foundation
import Testing

@testable import StoryArcCore

/// `library-portability` / *Secrets do not travel*, and `AGENTS.md` non-negotiable 4.
///
/// The non-negotiable names backups, and an export is a backup. So this suite does not check
/// that a particular field is absent — it checks the **bytes**, because a secret that reached
/// the file through a route nobody thought of is the failure this is here to catch. Android's
/// `LibraryExportSecrecyTest` runs the same three secrets past the same four spellings.
@Suite("No source secret reaches the exported bytes")
struct LibraryExportSecrecyTests {

    private let password = "hunter2correcthorse"
    private let token = "eyJhbGciOiJIUzI1NiJ9.aGVsbG8.sig"
    private let apiKey = "ak-9f3c2b1a7e5d4c6b8a0f2e1d3c4b5a69"

    /// Every place a secret has ever ended up in a locator, in one library.
    private var snapshot: LibrarySnapshot {
        LibrarySnapshot(
            sources: SourceRegistry(sources: [
                Source(
                    id: LibraryDocumentFixture.fixed("aaaaaaaa-0000-0000-0000-000000000001"),
                    displayName: "Share",
                    kind: .networkShare,
                    credentialReference: "keychain:share",
                    locator: "smb://reader:\(password)@nas.local/comics"
                ),
                Source(
                    id: LibraryDocumentFixture.fixed("aaaaaaaa-0000-0000-0000-000000000002"),
                    displayName: "Catalogue",
                    kind: .opdsCatalog,
                    credentialReference: "keychain:catalogue",
                    locator: "https://opds.example/feed?access_token=\(token)&sort=new"
                ),
                Source(
                    id: LibraryDocumentFixture.fixed("aaaaaaaa-0000-0000-0000-000000000003"),
                    displayName: "Kavita",
                    kind: .kavitaServer,
                    credentialReference: "keychain:kavita",
                    locator: "https://kavita.example/api?apikey=\(apiKey)&library=3"
                ),
            ])
        )
    }

    private func exportedBytes() throws -> String {
        let document = LibraryExport.document(
            snapshot,
            appVersion: "10.14.0",
            writtenAt: Date(timeIntervalSince1970: 0)
        )
        return String(bytes: try LibraryDocumentCoder.encode(document), encoding: .utf8) ?? ""
    }

    @Test("A password, a token and an API key are in none of the four spellings")
    func noSecretInAnySpelling() throws {
        let bytes = try exportedBytes()

        for secret in [password, token, apiKey] {
            // Plain, which is how it sat in the locator.
            #expect(!bytes.contains(secret), "plain: \(secret)")
            // Base64, which is how an encoder that thought it was being careful would write it.
            #expect(!bytes.contains(Data(secret.utf8).base64EncodedString()), "base64: \(secret)")
            // Percent-encoded, which is how a URL would carry it.
            let escaped = secret.addingPercentEncoding(
                withAllowedCharacters: .alphanumerics
            ) ?? secret
            #expect(!bytes.contains(escaped), "percent-encoded: \(secret)")
            // Escaped for JSON, which is what a `/` or a `"` inside one would become.
            #expect(!bytes.contains(secret.replacing("/", with: "\\/")), "JSON-escaped: \(secret)")
        }
    }

    @Test("The secure-store handle does not travel either")
    func noCredentialHandle() throws {
        let bytes = try exportedBytes()

        // Not a secret, and useless on another device — but it is a key into *this* device's
        // keychain, and a file that names it invites the question of what it unlocks.
        #expect(!bytes.contains("keychain:"))
    }

    @Test("What travels is the address, the name, the username and the kind")
    func whatDoesTravel() throws {
        let bytes = try exportedBytes()

        // The export is useless if the scrubbing takes the server with the secret. This is
        // the other half of the claim, and the reason `ExportableAddress` is not
        // `DiagnosticRedaction`.
        #expect(bytes.contains("smb://reader@nas.local/comics"))
        #expect(bytes.contains("https://opds.example/feed?sort=new"))
        #expect(bytes.contains("https://kavita.example/api?library=3"))
        #expect(bytes.contains("\"needsSignIn\" : true"))
    }

    // MARK: Carrying secrets (task 5.3)

    /// What the three sources' handles open to, standing in for the secure store.
    private var stored: [String: String] {
        ["keychain:share": password, "keychain:catalogue": token, "keychain:kavita": apiKey]
    }

    private func sealedBytes(passphrase: String) throws -> (bytes: String, document: LibraryDocument) {
        let sealed = try LibraryExport.sealedSecrets(for: snapshot, passphrase: passphrase) { source in
            source.credentialReference.flatMap { stored[$0] }
        }
        let document = LibraryExport.document(
            snapshot,
            appVersion: "10.14.0",
            writtenAt: Date(timeIntervalSince1970: 0),
            secrets: sealed
        )
        return (String(bytes: try LibraryDocumentCoder.encode(document), encoding: .utf8) ?? "", document)
    }

    @Test("With the switch off the document has no secrets object at all")
    func offWritesNoSecretsObject() throws {
        #expect(!(try exportedBytes()).contains("\"secrets\""))
    }

    @Test("With the switch on there is a secrets object and no secret in any of the four spellings")
    func onWritesNoClearText() throws {
        let (bytes, document) = try sealedBytes(passphrase: "correct horse")

        #expect(document.secrets?.sealed.count == 3)
        #expect(bytes.contains("\"secrets\""))
        for secret in [password, token, apiKey] {
            #expect(!bytes.contains(secret), "plain: \(secret)")
            #expect(!bytes.contains(Data(secret.utf8).base64EncodedString()), "base64: \(secret)")
            let escaped = secret.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? secret
            #expect(!bytes.contains(escaped), "percent-encoded: \(secret)")
            #expect(!bytes.contains(secret.replacing("/", with: "\\/")), "JSON-escaped: \(secret)")
        }
        // Neither the passphrase nor the secure-store handle is written.
        #expect(!bytes.contains("correct horse"))
        #expect(!bytes.contains("keychain:"))
    }

    @Test("The sealed block opens to the stored secrets under the passphrase, and not under another")
    func theSealedBlockOpens() throws {
        let (_, document) = try sealedBytes(passphrase: "correct horse")
        let block = try #require(document.secrets)

        let opened = try LibrarySecretSealer.open(block, passphrase: "correct horse")

        #expect(Set(opened.values) == [password, token, apiKey])
        #expect(throws: LibrarySecretsFailure.wrongPassphraseOrDamaged) {
            try LibrarySecretSealer.open(block, passphrase: "battery staple")
        }
    }

    @Test("A source whose handle points at nothing is skipped, and no secrets means no block")
    func nothingToSealMeansNoBlock() throws {
        let none = try LibraryExport.sealedSecrets(for: snapshot, passphrase: "x") { _ in nil }

        #expect(none == nil)
    }

    @Test("The passphrase pair is refused when empty or when the two differ")
    func thePassphrasePair() {
        #expect(ExportPassphrase.problem("", confirmation: "") == .empty)
        #expect(ExportPassphrase.problem("abc", confirmation: "abd") == .mismatch)
        #expect(ExportPassphrase.problem("abc", confirmation: "") == .mismatch)
        #expect(ExportPassphrase.problem("abc", confirmation: "abc") == nil)
    }

    @Test("One passphrase typed composed and decomposed is the same passphrase")
    func thePairIgnoresTheSpellingOfAnAccent() {
        let composed = "pa\u{00E9}"
        let decomposed = "pae\u{0301}"

        #expect(ExportPassphrase.problem(composed, confirmation: decomposed) == nil)
    }
}

/// The scrubbing on its own, case by case.
@Suite("An exportable address keeps the server and drops the secret")
struct ExportableAddressTests {

    @Test("A password in a userinfo goes and the username stays")
    func userInfo() {
        #expect(
            ExportableAddress.withoutSecret("smb://reader:hunter2@nas.local/comics")
                == "smb://reader@nas.local/comics"
        )
    }

    @Test("A userinfo with no password is left alone")
    func userInfoWithoutPassword() {
        #expect(
            ExportableAddress.withoutSecret("smb://reader@nas.local/comics")
                == "smb://reader@nas.local/comics"
        )
    }

    @Test("Every parameter name that means secret is dropped, and the others stay")
    func queryItems() {
        for name in ExportableAddress.secretNames {
            #expect(
                ExportableAddress.withoutSecret("https://h/f?\(name)=s&page=2")
                    == "https://h/f?page=2"
            )
        }
    }

    @Test("A secret in a fragment is dropped, like one in a query")
    func fragmentItems() {
        // A fragment never reaches a server, so it reads as harmless. It is still text in a
        // file the reader will carry to another device or hand to someone.
        #expect(ExportableAddress.withoutSecret("https://h/f#token=abc") == "https://h/f")
        #expect(
            ExportableAddress.withoutSecret("https://h/f?page=2&apikey=s#chapter-3")
                == "https://h/f?page=2#chapter-3"
        )
    }

    @Test("A fragment that names no secret is kept")
    func fragmentKept() {
        #expect(
            ExportableAddress.withoutSecret("https://h/f#chapter-3") == "https://h/f#chapter-3"
        )
    }

    @Test("A parameter name is matched whatever its case")
    func queryItemCase() {
        #expect(ExportableAddress.withoutSecret("https://h/f?ApiKey=s") == "https://h/f")
    }

    @Test("A folder path has nowhere for a secret to hide and is returned as it stands")
    func plainPath() {
        #expect(ExportableAddress.withoutSecret("/Books/Shelf") == "/Books/Shelf")
        #expect(
            ExportableAddress.withoutSecret("content://tree/primary%3AComics")
                == "content://tree/primary%3AComics"
        )
    }
}
