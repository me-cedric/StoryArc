package app.storyarc.core.playback

import app.storyarc.core.persistence.SettingsStore
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.android.controller.ServiceController
import org.robolectric.annotation.Config

/**
 * Task 15.5: `PlaybackService` is a `Context` of its own with no activity above it, so its
 * base context used to stay in the system's language. It now overrides `attachBaseContext`
 * the way `MainActivity` does.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class PlaybackServiceLanguageTest {

    private val context = RuntimeEnvironment.getApplication()
    private var service: ServiceController<PlaybackService>? = null

    @After
    fun quiet() {
        service?.destroy()
        service = null
    }

    @Test
    fun `the service's own context follows the chosen language`() {
        val store = SettingsStore.open(context)
        store.save(store.settings().copy(language = "fr"))

        val controller = Robolectric.buildService(PlaybackService::class.java).create()
        service = controller

        assertEquals("fr", controller.get().resources.configuration.locales[0].language)
    }
}
