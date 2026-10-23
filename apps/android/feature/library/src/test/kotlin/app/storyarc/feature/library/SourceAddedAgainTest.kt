package app.storyarc.feature.library

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceKind
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Task 28.6: adding a source at the same locator replaces the source rather than adding a
 * second row. iOS's `LibrarySourcesTests` ('Adding a place again with a new sign-in removes the
 * old secret') makes the same claim; the secret half needs the Keystore and is read in
 * `LibraryViewModel.addSource` rather than asserted here.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SourceAddedAgainTest {

    private fun library() = LibraryViewModel(ApplicationProvider.getApplicationContext<Application>())

    private fun share(name: String, reference: String) = Source(
        displayName = name,
        kind = SourceKind.NETWORK_SHARE,
        state = SourceConnectionState.Connected,
        credentialReference = reference,
        locator = "smb://127.0.0.1:4448/Sync",
    )

    @Test
    fun `the same place again is one source, under its first identifier, with the new sign-in`() {
        val library = library()
        val first = share("Sync", "ref-1")
        library.addSource(first)

        library.addSource(share("127.0.0.1/Sync", "ref-2"))

        val sources = library._registry.value.sources
        assertEquals(1, sources.size)
        assertEquals(first.id, sources.single().id)
        assertEquals("ref-2", sources.single().credentialReference)
        assertEquals("Sync", sources.single().displayName)
    }

    @Test
    fun `another place of the same kind is a second source`() {
        val library = library()
        library.addSource(share("Sync", "ref-1"))

        library.addSource(share("Comics", "ref-2").copy(locator = "smb://nas.local/Comics"))

        assertEquals(2, library._registry.value.sources.size)
    }
}
