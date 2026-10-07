package app.storyarc.core.model

import java.text.Normalizer
import java.util.Base64
import java.util.UUID
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `library-portability` task 5.2: a secret sealed under a passphrase, and opened again.
 *
 * `packages/test-fixtures/library/sealed-secrets.json` is one vector, sealed once by a third
 * implementation (Python's `cryptography`, not either app). Both platforms' suites open it, and
 * both seal the same inputs to the same bytes, so the two cannot drift. iOS's
 * `LibrarySecretSealerTests` asserts the same rows.
 */
class LibrarySecretSealerTest {

    @Serializable
    private class Vector(
        val passphrase: String,
        val plaintexts: Map<String, String>,
        val secrets: LibrarySecrets,
    )

    private val vector: Vector =
        Json.decodeFromString(LibraryDocumentFixture.document("sealed-secrets.json"))

    private val plaintexts: Map<UUID, String> =
        vector.plaintexts.mapKeys { UUID.fromString(it.key) }

    private fun flipped(base64: String, index: Int): String {
        val bytes = Base64.getDecoder().decode(base64)
        bytes[index] = (bytes[index].toInt() xor 1).toByte()
        return Base64.getEncoder().encodeToString(bytes)
    }

    private fun failure(block: () -> Unit): LibrarySecretsFailure? =
        runCatching(block).exceptionOrNull()?.let { (it as? LibrarySecretsException)?.failure }

    @Test
    fun `the committed vector opens under its passphrase, on this platform`() {
        assertEquals(plaintexts, LibrarySecretSealer.open(vector.secrets, vector.passphrase))
    }

    @Test
    fun `the same passphrase typed in decomposed form opens it too`() {
        val decomposed = Normalizer.normalize(vector.passphrase, Normalizer.Form.NFD)
        assertNotEquals(vector.passphrase.length, decomposed.length)

        assertEquals(plaintexts, LibrarySecretSealer.open(vector.secrets, decomposed))
    }

    @Test
    fun `this platform seals the vector's inputs to the vector's own bytes`() {
        val ids = plaintexts.keys.sortedBy { it.toString() }
        val nonces = ids.withIndex().associate { (offset, id) ->
            id to ByteArray(12) { (0x20 + offset * 0x10 + it).toByte() }
        }

        val sealed = LibrarySecretSealer.seal(
            plaintexts,
            vector.passphrase,
            salt = ByteArray(16) { it.toByte() },
            nonces = nonces,
        )

        assertEquals(vector.secrets, sealed)
    }

    @Test
    fun `a wrong passphrase opens nothing`() {
        assertEquals(
            LibrarySecretsFailure.WRONG_PASSPHRASE_OR_DAMAGED,
            failure { LibrarySecretSealer.open(vector.secrets, "not the passphrase") },
        )
    }

    @Test
    fun `a changed byte in the ciphertext, in its tag or in its nonce opens nothing`() {
        val key = vector.secrets.sealed.keys.sorted().first()
        val entry = vector.secrets.sealed.getValue(key)

        val changes = listOf(
            SealedSecret(entry.nonce, flipped(entry.ciphertext, 0)),
            SealedSecret(entry.nonce, flipped(entry.ciphertext, 20)),
            SealedSecret(flipped(entry.nonce, 0), entry.ciphertext),
        )
        for (change in changes) {
            val damaged = vector.secrets.copy(sealed = vector.secrets.sealed + (key to change))
            assertEquals(
                LibrarySecretsFailure.WRONG_PASSPHRASE_OR_DAMAGED,
                failure { LibrarySecretSealer.open(damaged, vector.passphrase) },
            )
        }
    }

    @Test
    fun `a fresh seal opens again, with a salt and a nonce of its own each time`() {
        val secrets = mapOf(LibraryDocumentFixture.networkShareId to "correct horse")

        val first = LibrarySecretSealer.seal(secrets, "battery staple")
        val second = LibrarySecretSealer.seal(secrets, "battery staple")

        assertEquals(secrets, LibrarySecretSealer.open(first, "battery staple"))
        assertNotEquals(first.salt, second.salt)
        assertNotEquals(first.sealed.values.map { it.nonce }, second.sealed.values.map { it.nonce })
        assertTrue(first.iterations >= 600_000)
        assertEquals("PBKDF2-HMAC-SHA256", first.kdf)
        assertEquals("AES-256-GCM", first.cipher)
    }

    @Test
    fun `a block this build does not read is refused by name`() {
        val changes = listOf(
            vector.secrets.copy(kdf = "scrypt"),
            vector.secrets.copy(cipher = "ChaCha20-Poly1305"),
            vector.secrets.copy(iterations = 0),
            vector.secrets.copy(iterations = LibrarySecretSealer.MAXIMUM_ITERATIONS + 1),
        )
        for (changed in changes) {
            assertEquals(
                LibrarySecretsFailure.UNSUPPORTED,
                failure { LibrarySecretSealer.open(changed, vector.passphrase) },
            )
        }
    }

    @Test
    fun `a nonce of the wrong length is malformed, not a wrong passphrase`() {
        val key = vector.secrets.sealed.keys.first()
        val short = SealedSecret(
            Base64.getEncoder().encodeToString(byteArrayOf(1, 2, 3)),
            vector.secrets.sealed.getValue(key).ciphertext,
        )
        val damaged = vector.secrets.copy(sealed = vector.secrets.sealed + (key to short))

        assertEquals(
            LibrarySecretsFailure.MALFORMED,
            failure { LibrarySecretSealer.open(damaged, vector.passphrase) },
        )
    }

    @Test
    fun `no passphrase is not a passphrase`() {
        assertEquals(
            LibrarySecretsFailure.EMPTY_PASSPHRASE,
            failure { LibrarySecretSealer.seal(mapOf(LibraryDocumentFixture.kavitaId to "x"), "") },
        )
    }

    @Test
    fun `a document carries the sealed block, and the secret is in none of its bytes`() {
        val secret = "a-secret-nobody-may-read-7c1f"
        val sealed = LibrarySecretSealer.seal(
            mapOf(LibraryDocumentFixture.networkShareId to secret),
            "battery staple",
        )
        val document = LibraryExport.document(
            LibraryDocumentFixture.snapshot,
            LibraryDocumentFixture.APP_VERSION,
            LibraryDocumentFixture.WRITTEN_AT,
            secrets = sealed,
        )

        val text = LibraryDocumentCoder.encode(document)
        val read = LibraryDocumentCoder.decode(text).getOrThrow()

        assertFalse(text.contains(secret))
        assertFalse(text.contains("battery staple"))
        assertEquals(sealed, read.secrets)
        assertEquals(
            mapOf(LibraryDocumentFixture.networkShareId to secret),
            LibrarySecretSealer.open(read.secrets!!, "battery staple"),
        )
    }
}
