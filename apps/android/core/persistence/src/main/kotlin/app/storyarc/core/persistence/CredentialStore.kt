package app.storyarc.core.persistence

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Source secrets, encrypted by a key the app cannot read.
 *
 * `sources` requires every secret — password, API key or token — to live in "the platform
 * secure store", and requires that a secret is never written to "preferences, logs, crash
 * reports, backups, or exported diagnostics". The registry holds an opaque reference and
 * nothing else, which is what makes that promise structural rather than a habit.
 *
 * **Not `EncryptedSharedPreferences`, although the requirement names it.** That class and
 * its `MasterKey` are deprecated in `androidx.security:security-crypto` 1.1.0 with no
 * replacement offered, and this project compiles with `allWarningsAsErrors`. What it did is
 * what this does: an AES-256-GCM key held in the Android Keystore, ciphertext in an
 * ordinary preference. The Keystore is the platform secure store the requirement means —
 * the key never enters the app's memory, only the cipher does.
 *
 * One entry per source, keyed by the source's identifier. Not one entry holding a map:
 * removing a source has to remove exactly its own secret, and a shared blob makes that a
 * read, an edit and a write where it should be a delete.
 *
 * iOS's `CredentialStore` is the same four operations against the Keychain.
 */
class CredentialStore internal constructor(
    private val preferences: SharedPreferences,
    private val key: SecretKey,
) {

    companion object {
        private const val KEYSTORE = "AndroidKeyStore"
        private const val KEY_ALIAS = "app.storyarc.credentials"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"

        /** 96 bits, which is what GCM is specified for and what the platform generates. */
        private const val NONCE_BYTES = 12

        /** 128-bit tag, the longest GCM offers. */
        private const val TAG_BITS = 128

        /**
         * Opens the store, or returns null when the device refuses to give a key.
         *
         * Null rather than a throw, and rather than a plaintext fallback. A device with no
         * usable keystore cannot hold a secret safely, and writing one to an ordinary
         * preference to keep the feature working is precisely what the requirement forbids.
         * A caller with no store refuses to save a source that needs one.
         */
        fun open(context: Context): CredentialStore? = runCatching {
            CredentialStore(
                context.getSharedPreferences("app.storyarc.credentials", Context.MODE_PRIVATE),
                key(),
            )
        }.getOrNull()

        /**
         * The reference a registry entry holds.
         *
         * The source's own identifier, and deliberately nothing else. A reference that
         * encoded anything about the secret would be a fact about the secret stored outside
         * the secure store.
         */
        fun reference(sourceId: UUID): String = sourceId.toString()

        /**
         * The app's one key, created on first use.
         *
         * `setUserAuthenticationRequired` is deliberately *not* set. A reader who has
         * unlocked their phone has authenticated, and asking again to open a book they
         * configured is the kind of friction that teaches people to leave a library
         * unconfigured. `setRandomizedEncryptionRequired` stays on, so every save takes its
         * own nonce from the platform.
         */
        private fun key(): SecretKey {
            val store = KeyStore.getInstance(KEYSTORE).apply { load(null) }
            (store.getEntry(KEY_ALIAS, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }

            val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
            generator.init(
                KeyGenParameterSpec.Builder(
                    KEY_ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                )
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256)
                    .setRandomizedEncryptionRequired(true)
                    .build(),
            )
            return generator.generateKey()
        }
    }

    /**
     * Stores a secret, replacing whatever was there.
     *
     * The nonce goes in front of the ciphertext rather than into a second preference. It is
     * not a secret — GCM requires it to be unique per encryption, not hidden — and one
     * value is one thing to delete.
     */
    fun save(secret: String, reference: String): Boolean = runCatching {
        val cipher = Cipher.getInstance(TRANSFORMATION).apply { init(Cipher.ENCRYPT_MODE, key) }
        val sealed = cipher.iv + cipher.doFinal(secret.toByteArray())
        preferences.edit()
            .putString(reference, Base64.encodeToString(sealed, Base64.NO_WRAP))
            .commit()
    }.getOrDefault(false)

    /**
     * Reads a secret at the moment of use.
     *
     * Returned rather than cached, per the requirement: "it reads it from the secure store
     * at the moment of use and does not retain it beyond the request". Nothing in this class
     * holds one.
     *
     * A value that will not decrypt yields null rather than throwing. That happens when the
     * key is gone — a restore onto a new device, or a reader who cleared the app's keystore
     * entry — and the honest answer there is that the secret is unavailable and has to be
     * entered again.
     */
    fun secret(reference: String): String? = runCatching {
        val stored = preferences.getString(reference, null) ?: return null
        val sealed = Base64.decode(stored, Base64.NO_WRAP)
        val cipher = Cipher.getInstance(TRANSFORMATION).apply {
            init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(TAG_BITS, sealed, 0, NONCE_BYTES))
        }
        String(cipher.doFinal(sealed, NONCE_BYTES, sealed.size - NONCE_BYTES))
    }.getOrNull()

    /**
     * Forgets one source's secret.
     *
     * Called when a source is removed. `sources` requires removal to take "its stored
     * credentials" with it, and a secret outliving the source it belonged to is a secret
     * nobody will ever look for again. Removing one that was never there succeeds, because
     * source removal calls this whether or not the source had a secret — and a folder never
     * does.
     */
    fun remove(reference: String): Boolean =
        runCatching { preferences.edit().remove(reference).commit() }.getOrDefault(false)

    /**
     * Whether a secret is stored, without decrypting it.
     *
     * For a source list that shows whether a server is configured. Asking this rather than
     * calling [secret] and discarding the answer keeps the secret out of memory for a
     * question that never needed it.
     */
    fun hasSecret(reference: String): Boolean =
        runCatching { preferences.contains(reference) }.getOrDefault(false)
}
