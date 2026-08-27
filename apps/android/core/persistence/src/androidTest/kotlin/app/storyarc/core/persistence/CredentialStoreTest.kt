package app.storyarc.core.persistence

import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.util.UUID

/**
 * Source secrets: stored, read at the moment of use, and removed with the source.
 *
 * Instrumented, and not by choice. The whole point of this class is the Android Keystore,
 * and the unit-test android.jar stubs it — a JVM test here would assert against a mock of
 * the one thing under test. iOS's `CredentialStoreTests` runs against a real Keychain for
 * the same reason.
 */
class CredentialStoreTest {

    private lateinit var store: CredentialStore
    private val references = mutableListOf<String>()

    @Before
    fun open() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        store = requireNotNull(CredentialStore.open(context)) { "no keystore on this device" }
    }

    @After
    fun clean() {
        references.forEach { store.remove(it) }
    }

    private fun reference(): String =
        CredentialStore.reference(UUID.randomUUID()).also { references.add(it) }

    @Test
    fun aStoredSecretReadsBack() {
        val reference = reference()

        assertTrue(store.save("hunter2", reference))
        assertEquals("hunter2", store.secret(reference))
    }

    @Test
    fun aReferenceNobodyStoredHasNoSecret() {
        assertNull(store.secret(reference()))
    }

    @Test
    fun savingTwiceReplacesRatherThanLeavingTwo() {
        // A duplicate is how a password change appears to work and then does not.
        val reference = reference()

        store.save("old", reference)
        store.save("new", reference)

        assertEquals("new", store.secret(reference))
    }

    @Test
    fun removingASourcesSecretTakesItWithIt() {
        // `sources` requires removal to take "its stored credentials" with it.
        val reference = reference()
        store.save("hunter2", reference)

        assertTrue(store.remove(reference))
        assertNull(store.secret(reference))
    }

    @Test
    fun removingNothingSucceedsSoRemovalIsIdempotent() {
        // Source removal calls this whether or not the source had a secret, and a folder
        // never does.
        assertTrue(store.remove(reference()))
    }

    @Test
    fun askingWhetherASecretExistsDoesNotReadIt() {
        val reference = reference()

        assertFalse(store.hasSecret(reference))
        store.save("hunter2", reference)
        assertTrue(store.hasSecret(reference))
    }

    @Test
    fun twoSourcesKeepTheirOwnSecrets() {
        // One entry per source rather than one blob holding all of them.
        val first = reference()
        val second = reference()
        store.save("first", first)
        store.save("second", second)

        store.remove(first)

        assertNull(store.secret(first))
        assertEquals("second", store.secret(second))
    }

    @Test
    fun theStoredValueIsNotThePlaintext() {
        // The point of the class. Reading the preference directly must not yield the
        // secret, or every promise `sources` makes about diagnostics and backups is void.
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val reference = reference()
        store.save("hunter2", reference)

        val raw = context
            .getSharedPreferences("app.storyarc.credentials", android.content.Context.MODE_PRIVATE)
            .getString(reference, null)

        assertNotNull(raw)
        assertFalse(raw!!.contains("hunter2"))
    }

    @Test
    fun twoSavesOfOneSecretProduceDifferentCiphertext()

    {
        // `setRandomizedEncryptionRequired` means a fresh nonce per save. Identical
        // ciphertext for identical plaintext would leak that two sources share a password.
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val preferences = context
            .getSharedPreferences("app.storyarc.credentials", android.content.Context.MODE_PRIVATE)
        val first = reference()
        val second = reference()

        store.save("hunter2", first)
        store.save("hunter2", second)

        assertFalse(preferences.getString(first, null) == preferences.getString(second, null))
    }
}
