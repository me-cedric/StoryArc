package app.storyarc.core.model

import java.net.URLEncoder
import java.util.Base64
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `library-portability` / *Secrets do not travel*, and `AGENTS.md` non-negotiable 4.
 *
 * The non-negotiable names backups, and an export is a backup. So this suite does not check
 * that a particular field is absent — it checks the **bytes**, because a secret that reached
 * the file through a route nobody thought of is the failure this is here to catch. iOS's
 * `LibraryExportSecrecyTests` runs the same three secrets past the same four spellings.
 */
class LibraryExportSecrecyTest {

    private val password = "hunter2correcthorse"
    private val token = "eyJhbGciOiJIUzI1NiJ9.aGVsbG8.sig"
    private val apiKey = "ak-9f3c2b1a7e5d4c6b8a0f2e1d3c4b5a69"

    /** Every place a secret has ever ended up in a locator, in one library. */
    private val snapshot = LibrarySnapshot(
        sources = SourceRegistry(
            sources = listOf(
                Source(
                    id = UUID.fromString("aaaaaaaa-0000-0000-0000-000000000001"),
                    displayName = "Share",
                    kind = SourceKind.NETWORK_SHARE,
                    credentialReference = "keystore:share",
                    locator = "smb://reader:$password@nas.local/comics",
                ),
                Source(
                    id = UUID.fromString("aaaaaaaa-0000-0000-0000-000000000002"),
                    displayName = "Catalogue",
                    kind = SourceKind.OPDS_CATALOG,
                    credentialReference = "keystore:catalogue",
                    locator = "https://opds.example/feed?access_token=$token&sort=new",
                ),
                Source(
                    id = UUID.fromString("aaaaaaaa-0000-0000-0000-000000000003"),
                    displayName = "Kavita",
                    kind = SourceKind.KAVITA_SERVER,
                    credentialReference = "keystore:kavita",
                    locator = "https://kavita.example/api?apikey=$apiKey&library=3",
                ),
            ),
        ),
    )

    private fun exportedBytes(): String =
        LibraryDocumentCoder.encode(LibraryExport.document(snapshot, "10.14.0", 0L))

    @Test
    fun `a password, a token and an api key are in none of the four spellings`() {
        val bytes = exportedBytes()

        for (secret in listOf(password, token, apiKey)) {
            // Plain, which is how it sat in the locator.
            assertFalse("plain: $secret", bytes.contains(secret))
            // Base64, which is how an encoder that thought it was being careful would write
            // it.
            assertFalse(
                "base64: $secret",
                bytes.contains(Base64.getEncoder().encodeToString(secret.toByteArray())),
            )
            // Percent-encoded, which is how a URL would carry it.
            assertFalse(
                "percent-encoded: $secret",
                bytes.contains(URLEncoder.encode(secret, Charsets.UTF_8)),
            )
            // Escaped for JSON, which is what a `/` or a `"` inside one would become.
            assertFalse("JSON-escaped: $secret", bytes.contains(secret.replace("/", "\\/")))
        }
    }

    @Test
    fun `the secure-store handle does not travel either`() {
        // Not a secret, and useless on another device — but it is a key into *this* device's
        // keystore, and a file that names it invites the question of what it unlocks.
        assertFalse(exportedBytes().contains("keystore:"))
    }

    @Test
    fun `what travels is the address, the name, the username and the kind`() {
        val bytes = exportedBytes()

        // The export is useless if the scrubbing takes the server with the secret. This is
        // the other half of the claim, and the reason `ExportableAddress` is not
        // `DiagnosticRedaction`.
        assertTrue(bytes.contains("smb://reader@nas.local/comics"))
        assertTrue(bytes.contains("https://opds.example/feed?sort=new"))
        assertTrue(bytes.contains("https://kavita.example/api?library=3"))
        assertTrue(bytes.contains("\"needsSignIn\": true"))
    }
}

/** The scrubbing on its own, case by case. */
class ExportableAddressTest {

    @Test
    fun `a password in a userinfo goes and the username stays`() {
        assertEquals(
            "smb://reader@nas.local/comics",
            ExportableAddress.withoutSecret("smb://reader:hunter2@nas.local/comics"),
        )
    }

    @Test
    fun `a userinfo with no password is left alone`() {
        assertEquals(
            "smb://reader@nas.local/comics",
            ExportableAddress.withoutSecret("smb://reader@nas.local/comics"),
        )
    }

    @Test
    fun `every parameter name that means secret is dropped, and the others stay`() {
        val names = listOf(
            "token", "password", "passwd", "pwd", "secret", "key", "apikey", "api_key",
            "api-key", "x-api-key", "auth", "authorization", "bearer", "accesstoken",
            "access_token", "refresh_token", "refreshtoken", "session", "sessionid",
            "session_id", "sid", "credential", "credentials", "signature", "sig",
        )
        for (name in names) {
            assertEquals(
                "https://h/f?page=2",
                ExportableAddress.withoutSecret("https://h/f?$name=s&page=2"),
            )
        }
    }

    @Test
    fun `a secret in a fragment is dropped, like one in a query`() {
        // A fragment never reaches a server, so it reads as harmless. It is still text in a
        // file the reader will carry to another device or hand to someone.
        assertEquals(
            "https://h/f",
            ExportableAddress.withoutSecret("https://h/f#token=abc"),
        )
        assertEquals(
            "https://h/f?page=2#chapter-3",
            ExportableAddress.withoutSecret("https://h/f?page=2&apikey=s#chapter-3"),
        )
    }

    @Test
    fun `a fragment that names no secret is kept`() {
        assertEquals(
            "https://h/f#chapter-3",
            ExportableAddress.withoutSecret("https://h/f#chapter-3"),
        )
    }

    @Test
    fun `a parameter name is matched whatever its case`() {
        assertEquals("https://h/f", ExportableAddress.withoutSecret("https://h/f?ApiKey=s"))
    }

    @Test
    fun `a folder tree uri has nowhere for a secret to hide and is returned as it stands`() {
        assertEquals("/Books/Shelf", ExportableAddress.withoutSecret("/Books/Shelf"))
        assertEquals(
            "content://tree/primary%3AComics",
            ExportableAddress.withoutSecret("content://tree/primary%3AComics"),
        )
    }
}
