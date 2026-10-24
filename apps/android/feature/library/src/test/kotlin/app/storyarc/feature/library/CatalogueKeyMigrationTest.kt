package app.storyarc.feature.library

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.catalogue.OpdsCredential
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
import app.storyarc.core.model.SourceRegistry
import app.storyarc.core.model.SourceTombstone
import app.storyarc.core.persistence.SourceSecretStore
import app.storyarc.core.persistence.SourceStore
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * A catalogue row saved before 2026-10-24 loses its feed key to the secure store on the first
 * launch, and nothing else changes on any launch after that.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class CatalogueKeyMigrationTest {

    private val application: Application get() = ApplicationProvider.getApplicationContext()

    /** A secure store in memory that counts its writes, and can refuse them. */
    private class Secrets(private val accepts: Boolean = true) : SourceSecretStore {
        val held = mutableMapOf<String, String>()
        var saves = 0

        override fun save(secret: String, reference: String): Boolean {
            saves++
            if (accepts) held[reference] = secret
            return accepts
        }

        override fun secret(reference: String): String? = held[reference]

        override fun remove(reference: String): Boolean = held.remove(reference) != null
    }

    private val id = UUID.fromString("77777777-7777-7777-7777-777777777777")

    private fun catalogue(locator: String, reference: String? = null) = Source(
        id = id,
        displayName = "Books",
        kind = SourceKind.OPDS_CATALOG,
        credentialReference = reference,
        locator = locator,
    )

    private fun store(vararg sources: Source) =
        SourceStore.open(application).apply { save(SourceRegistry(sources = sources.toList())) }

    @Test
    fun `a legacy row's key moves to the secure store and the locator loses it`() {
        val typed = "https://books.example/opds?shelf=comics&apikey=k1"
        val store = store(catalogue(typed))
        val secrets = Secrets()

        store.movingCatalogueKeys(secrets)

        val row = store.registry().sources.single()
        assertEquals("https://books.example/opds?shelf=comics", row.locator)
        assertEquals(id.toString(), row.credentialReference)
        val stored = secrets.held.getValue(id.toString())
        assertEquals(typed, CatalogueTarget.withQuery(row.locator!!, OpdsCredential.query(stored)))
        assertNull(OpdsCredential.of(stored))
    }

    @Test
    fun `a key merges with the sign-in already stored for the row`() {
        val store = store(catalogue("https://books.example/opds?token=t2", reference = "held"))
        val secrets = Secrets().apply { held["held"] = OpdsCredential.Basic("reader", "hunter2").stored }

        store.movingCatalogueKeys(secrets)

        val row = store.registry().sources.single()
        assertEquals("https://books.example/opds", row.locator)
        assertEquals("held", row.credentialReference)
        val stored = secrets.held.getValue("held")
        assertEquals(OpdsCredential.stored(OpdsCredential.Basic("reader", "hunter2"), "token=t2"), stored)
        assertEquals(OpdsCredential.Basic("reader", "hunter2"), OpdsCredential.of(stored))
    }

    @Test
    fun `a password in the address moves too`() {
        val store = store(catalogue("https://reader:hunter2@books.example/opds"))
        val secrets = Secrets()

        store.movingCatalogueKeys(secrets)

        assertEquals("https://books.example/opds", store.registry().sources.single().locator)
        assertEquals(
            OpdsCredential.Basic("reader", "hunter2"),
            OpdsCredential.of(secrets.held.getValue(id.toString())),
        )
    }

    @Test
    fun `a clean row, another kind, and a second run are left alone`() {
        val clean = catalogue("https://books.example/opds?shelf=comics")
        val kavita = Source(displayName = "Kavita", kind = SourceKind.KAVITA_SERVER, locator = "https://k.example/?key=x")
        val store = store(clean, kavita)
        val secrets = Secrets()

        store.movingCatalogueKeys(secrets)

        assertEquals(listOf(clean.locator, kavita.locator), store.registry().sources.map { it.locator })
        assertEquals(0, secrets.saves)

        val legacy = store(catalogue("https://books.example/opds?apikey=k1"))
        legacy.movingCatalogueKeys(secrets)
        val first = legacy.registry()
        val held = secrets.held.toMap()
        legacy.movingCatalogueKeys(secrets)

        assertEquals(first, legacy.registry())
        assertEquals(held, secrets.held)
        assertEquals(1, secrets.saves)
    }

    @Test
    fun `a store that refuses the key leaves the row as it was`() {
        val typed = "https://books.example/opds?apikey=k1"
        val store = store(catalogue(typed))

        store.movingCatalogueKeys(Secrets(accepts = false))
        assertEquals(typed, store.registry().sources.single().locator)

        store.movingCatalogueKeys(null)
        assertEquals(typed, store.registry().sources.single().locator)
        assertNull(store.registry().sources.single().credentialReference)
    }

    @Test
    fun `a catalogue's tombstone loses its key`() {
        val store = SourceStore.open(application).apply {
            save(
                SourceRegistry(
                    tombstones = listOf(
                        SourceTombstone(id, 1L, SourceKind.OPDS_CATALOG, "https://books.example/opds?apikey=k1"),
                    ),
                ),
            )
        }

        store.movingCatalogueKeys(Secrets())

        assertEquals("https://books.example/opds", store.registry().tombstones.single().locator)
    }

    @Test
    fun `a restored row with no stored secret builds a page with no credential`() {
        // A restore brings the row back without the device-bound key, so the secret reads null.
        val page = CataloguePage.of(catalogue("https://books.example/opds", reference = "gone"), null)!!

        assertEquals("https://books.example/opds", page.url)
        assertNull(page.credential)
    }
}
