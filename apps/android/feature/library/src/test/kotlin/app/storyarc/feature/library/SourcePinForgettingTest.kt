package app.storyarc.feature.library

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.catalogue.CertificatePins
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
import app.storyarc.core.persistence.CertificatePinStore
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * 11.9: `CertificatePins.forget` and `CertificatePinStore.forget` are documented as "called
 * when its source is removed", and nothing called either of them -- removing a pinned
 * catalogue left the pin live for whatever reader or server next answered at that host.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SourcePinForgettingTest {

    private val host = "books.example"
    private val fingerprint = "6B:D2:93"

    private fun library() = LibraryViewModel(ApplicationProvider.getApplicationContext<Application>())

    private fun catalogue(locator: String = "https://$host/feed") =
        Source(displayName = "Library", kind = SourceKind.OPDS_CATALOG, locator = locator)

    private fun pinStore() = CertificatePinStore.open(ApplicationProvider.getApplicationContext())

    @Test
    fun `removing a source's only catalogue at a host forgets its pin`() {
        val library = library()
        val source = catalogue()
        library.addSource(source)
        val pins = CertificatePins(mapOf(host to setOf(fingerprint)))
        val store = pinStore().also { it.save(pins.all) }

        library.forgetPinIfUnshared(source, pins, store)

        assertFalse(pins.accepts(fingerprint, host))
        assertTrue(store.pins()[host].orEmpty().isEmpty())
    }

    @Test
    fun `a pin stays while another saved source answers at the same host`() {
        val library = library()
        val removed = catalogue()
        val kept = catalogue().copy(kind = SourceKind.KAVITA_SERVER)
        library.addSource(removed)
        library.addSource(kept)
        val pins = CertificatePins(mapOf(host to setOf(fingerprint)))
        val store = pinStore().also { it.save(pins.all) }

        library.forgetPinIfUnshared(removed, pins, store)

        assertTrue(pins.accepts(fingerprint, host))
        assertTrue(store.pins()[host].orEmpty().contains(fingerprint))
    }
}
