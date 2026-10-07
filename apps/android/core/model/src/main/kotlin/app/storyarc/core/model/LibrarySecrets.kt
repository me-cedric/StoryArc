package app.storyarc.core.model

import java.security.GeneralSecurityException
import java.security.SecureRandom
import java.text.Normalizer
import java.util.Base64
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec
import kotlinx.serialization.Serializable

/**
 * The passphrase-sealed credential block of a library document.
 *
 * `library-portability` / *Secrets travel only sealed, and only when asked*: each secret is
 * written only as ciphertext, keyed by its source, and every parameter is in the document, so a
 * hard-coded iteration count cannot trap a file already written. iOS's `LibrarySecrets` is the
 * same shape. The `packages/test-fixtures/library/sealed-secrets.json` vector is opened by both
 * platforms' tests.
 *
 * The writer fills this only when the reader chose to carry secrets and gave a passphrase.
 */
@Serializable
data class LibrarySecrets(
    val kdf: String,
    val iterations: Int,
    /** The salt, in base64. One per document. */
    val salt: String,
    val cipher: String,
    /** One sealed secret per source, keyed by the source id in lower case. */
    val sealed: Map<String, SealedSecret> = emptyMap(),
)

/**
 * One secret as ciphertext: the nonce it was sealed with, and the ciphertext followed by the
 * 128-bit tag, both in base64.
 */
@Serializable
data class SealedSecret(val nonce: String, val ciphertext: String)

/** Why a block of secrets could not be sealed or opened. */
enum class LibrarySecretsFailure {
    /** The reader gave no passphrase. */
    EMPTY_PASSPHRASE,

    /** A KDF, a cipher or an iteration count this build does not read. */
    UNSUPPORTED,

    /** A field that is not base64, or has the wrong length. */
    MALFORMED,

    /**
     * The passphrase is wrong, or the ciphertext was changed. AES-GCM cannot tell the two apart,
     * and the reader's next step is the same for both.
     */
    WRONG_PASSPHRASE_OR_DAMAGED,
}

/** The exception a refused block of secrets arrives as; [failure] is the part callers read. */
class LibrarySecretsException(val failure: LibrarySecretsFailure) : Exception(failure.name)

/**
 * Seals and opens secrets under a passphrase.
 *
 * PBKDF2-HMAC-SHA256 at 600,000 iterations derives a 32-byte key from the passphrase and a
 * random 16-byte salt. Each secret is sealed with AES-256-GCM under that key, with its own
 * random 12-byte nonce and a 128-bit tag. No dependency: `javax.crypto`.
 *
 * The passphrase is normalised to NFC before its UTF-8 bytes are taken, so one passphrase typed
 * on two keyboards is one key on both platforms. iOS's `LibrarySecretSealer` does the same.
 */
object LibrarySecretSealer {
    const val KDF_NAME = "PBKDF2-HMAC-SHA256"
    const val CIPHER_NAME = "AES-256-GCM"

    /** OWASP's figure for PBKDF2-HMAC-SHA256 when this was written. Always what the writer uses. */
    const val ITERATIONS = 600_000

    /**
     * The most iterations a document may ask this build to run. A document is untrusted input,
     * and an iteration count of four billion is a way to hang the app.
     */
    const val MAXIMUM_ITERATIONS = 10_000_000

    private const val SALT_LENGTH = 16
    private const val NONCE_LENGTH = 12
    private const val KEY_BITS = 256
    private const val TAG_BITS = 128
    private const val TAG_LENGTH = TAG_BITS / 8

    private val random = SecureRandom()

    /** Seals each secret under [passphrase], with a fresh salt and a fresh nonce for each. */
    fun seal(secrets: Map<UUID, String>, passphrase: String): LibrarySecrets =
        seal(
            secrets,
            passphrase,
            salt = randomBytes(SALT_LENGTH),
            nonces = secrets.mapValues { randomBytes(NONCE_LENGTH) },
        )

    /**
     * The same, with the salt and the nonces chosen by the caller. Fixed inputs make the output
     * fixed, which is how the committed test vector is checked.
     */
    internal fun seal(
        secrets: Map<UUID, String>,
        passphrase: String,
        salt: ByteArray,
        nonces: Map<UUID, ByteArray>,
    ): LibrarySecrets {
        val key = derivedKey(passphrase, salt, ITERATIONS)
        val encoder = Base64.getEncoder()
        val sealed = secrets.entries.associate { (id, secret) ->
            val nonce = nonces[id]?.takeIf { it.size == NONCE_LENGTH }
                ?: throw LibrarySecretsException(LibrarySecretsFailure.MALFORMED)
            val ciphertext = cipher(Cipher.ENCRYPT_MODE, key, nonce).doFinal(secret.toByteArray())
            id.toString().lowercase() to
                SealedSecret(encoder.encodeToString(nonce), encoder.encodeToString(ciphertext))
        }
        return LibrarySecrets(KDF_NAME, ITERATIONS, encoder.encodeToString(salt), CIPHER_NAME, sealed)
    }

    /**
     * Every secret, by the id of its source.
     *
     * All or nothing: one secret that does not open fails the call. A wrong passphrase fails
     * every secret at once, and a changed byte fails its own, so there is no partial answer the
     * reader could act on better than "this passphrase did not open the file".
     */
    fun open(secrets: LibrarySecrets, passphrase: String): Map<UUID, String> {
        if (secrets.kdf != KDF_NAME || secrets.cipher != CIPHER_NAME ||
            secrets.iterations !in 1..MAXIMUM_ITERATIONS
        ) {
            throw LibrarySecretsException(LibrarySecretsFailure.UNSUPPORTED)
        }
        val salt = decode(secrets.salt)?.takeIf { it.isNotEmpty() }
            ?: throw LibrarySecretsException(LibrarySecretsFailure.MALFORMED)

        val key = derivedKey(passphrase, salt, secrets.iterations)
        return secrets.sealed.entries.associate { (name, entry) ->
            val id = runCatching { UUID.fromString(name) }.getOrNull()
            val nonce = decode(entry.nonce)?.takeIf { it.size == NONCE_LENGTH }
            val combined = decode(entry.ciphertext)?.takeIf { it.size >= TAG_LENGTH }
            if (id == null || nonce == null || combined == null) {
                throw LibrarySecretsException(LibrarySecretsFailure.MALFORMED)
            }
            val plain = try {
                cipher(Cipher.DECRYPT_MODE, key, nonce).doFinal(combined)
            } catch (_: GeneralSecurityException) {
                throw LibrarySecretsException(LibrarySecretsFailure.WRONG_PASSPHRASE_OR_DAMAGED)
            }
            id to plain.toString(Charsets.UTF_8)
        }
    }

    private fun cipher(mode: Int, key: SecretKeySpec, nonce: ByteArray): Cipher =
        Cipher.getInstance("AES/GCM/NoPadding").apply {
            init(mode, key, GCMParameterSpec(TAG_BITS, nonce))
        }

    private fun derivedKey(passphrase: String, salt: ByteArray, iterations: Int): SecretKeySpec {
        val normalised = Normalizer.normalize(passphrase, Normalizer.Form.NFC)
        if (normalised.isEmpty()) {
            throw LibrarySecretsException(LibrarySecretsFailure.EMPTY_PASSPHRASE)
        }
        val spec = PBEKeySpec(normalised.toCharArray(), salt, iterations, KEY_BITS)
        try {
            val bytes = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).encoded
            return SecretKeySpec(bytes, "AES")
        } finally {
            spec.clearPassword()
        }
    }

    private fun decode(text: String): ByteArray? =
        runCatching { Base64.getDecoder().decode(text) }.getOrNull()

    private fun randomBytes(count: Int): ByteArray = ByteArray(count).also(random::nextBytes)
}
