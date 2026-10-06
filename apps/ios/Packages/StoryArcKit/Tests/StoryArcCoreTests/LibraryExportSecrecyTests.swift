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
