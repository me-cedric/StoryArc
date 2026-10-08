package app.storyarc.core.model

import java.util.UUID
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `library-portability` task 5.4: which sources an import gives a secret to, and what the merge
 * does with one it opened. iOS's `LibraryImportSecretsTests` asserts the same rows.
 *
 * The document is sealed by the committed vector, which a third implementation made, so the
 * block here is what the other platform's export would hold.
 */
class LibraryImportSecretsTest {

    @Serializable
    private class Vector(
        val passphrase: String,
        val plaintexts: Map<String, String>,
        val secrets: LibrarySecrets,
    )

    private val vector: Vector =
        Json.decodeFromString(LibraryDocumentFixture.document("sealed-secrets.json"))

    private val sealedDocument = LibraryExport.document(
        LibraryDocumentFixture.snapshot,
        LibraryDocumentFixture.APP_VERSION,
        LibraryDocumentFixture.WRITTEN_AT,
        secrets = vector.secrets,
    )

    private val opened: Map<UUID, String> = LibrarySecretSealer.open(vector.secrets, vector.passphrase)

    private val empty = LibrarySnapshot()
    private val share = LibraryDocumentFixture.networkShareId
    private val kavita = LibraryDocumentFixture.kavitaId

    @Test
    fun `a document with sealed secrets for sources it brings needs a passphrase`() {
        assertTrue(LibraryImport.needsPassphrase(sealedDocument, empty))
        assertEquals(setOf(share, kavita), LibraryImport.fillableSources(sealedDocument, empty))
    }

    @Test
    fun `a document with no secrets asks for nothing`() {
        val plain = LibraryExport.document(
            LibraryDocumentFixture.snapshot,
            LibraryDocumentFixture.APP_VERSION,
            LibraryDocumentFixture.WRITTEN_AT,
        )

        assertFalse(LibraryImport.needsPassphrase(plain, empty))
    }

    @Test
    fun `a source this device is already signed in to keeps its own secret`() {
        val device = LibrarySnapshot(
            sources = SourceRegistry(
                sources = listOf(
                    Source(id = share, displayName = "Comics NAS", kind = SourceKind.NETWORK_SHARE, credentialReference = "mine"),
                ),
            ),
        )

        val result = LibraryImport.merging(sealedDocument, device, opened) { it.toString() }

        assertEquals(setOf(kavita), LibraryImport.fillableSources(sealedDocument, device))
        assertEquals(setOf(kavita), result.credentialed)
        assertEquals("mine", result.snapshot.sources.sources.first { it.id == share }.credentialReference)
    }

    @Test
    fun `a source the device holds with no secret is given the one the document carries`() {
        val device = LibrarySnapshot(
            sources = SourceRegistry(
                sources = listOf(Source(id = kavita, displayName = "My Kavita", kind = SourceKind.KAVITA_SERVER)),
            ),
        )

        val result = LibraryImport.merging(sealedDocument, device, opened) { "ref:$it" }
        val held = result.snapshot.sources.sources.first { it.id == kavita }

        assertEquals("ref:$kavita", held.credentialReference)
        // The device's own name for it stands.
        assertEquals("My Kavita", held.displayName)
    }

    @Test
    fun `a source given a secret gets its handle and is no longer listed as needing a sign-in`() {
        val result = LibraryImport.merging(sealedDocument, empty, opened) { it.toString() }

        assertEquals(
            share.toString(),
            result.snapshot.sources.sources.first { it.id == share }.credentialReference,
        )
        assertEquals(setOf(share, kavita), result.credentialed)
        assertTrue(result.sourcesNeedingSignIn.isEmpty())
    }

    @Test
    fun `without opened secrets every source that held one asks for a sign-in`() {
        val result = LibraryImport.merging(sealedDocument, empty, emptyMap()) { it.toString() }

        assertTrue(result.credentialed.isEmpty())
        assertEquals(listOf("Comics NAS", "Kavita"), result.sourcesNeedingSignIn)
        assertTrue(result.snapshot.sources.sources.all { it.credentialReference == null })
    }

    @Test
    fun `a secret for a source the document does not carry is ignored`() {
        val stranger = UUID.fromString("99999999-9999-9999-9999-999999999999")

        val result = LibraryImport.merging(sealedDocument, empty, mapOf(stranger to "x")) { it.toString() }

        assertTrue(result.credentialed.isEmpty())
    }
}
