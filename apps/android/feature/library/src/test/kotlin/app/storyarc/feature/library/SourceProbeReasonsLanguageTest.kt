package app.storyarc.feature.library

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.persistence.SettingsStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Task 15.5: `speakingReaderLanguage()`, the wrap `LibraryViewModel.testSource` and
 * `SourceRetry.probeEverySource` both use for their two reasons, actually resolves in the
 * reader's chosen language rather than the system's. Reading `application.getString(...)`
 * directly, as both used to, reads only the system's.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SourceProbeReasonsLanguageTest {

    private val application: Application get() = ApplicationProvider.getApplicationContext()

    @Test
    fun `the unauthorized reason reads in the chosen language, not the system's`() {
        val store = SettingsStore.open(application)
        store.save(store.settings().copy(language = "fr"))

        val speaking = application.speakingReaderLanguage()

        assertEquals("Connexion requise", speaking.getString(R.string.source_state_unauthorized))
        assertNotEquals(
            application.getString(R.string.source_state_unauthorized),
            speaking.getString(R.string.source_state_unauthorized),
        )
    }

    @Test
    fun `with no language chosen, the wrapped context answers exactly what the bare one does`() {
        val store = SettingsStore.open(application)
        store.save(store.settings().copy(language = null))

        val speaking = application.speakingReaderLanguage()

        assertEquals(
            application.getString(R.string.source_state_unauthorized),
            speaking.getString(R.string.source_state_unauthorized),
        )
    }
}
