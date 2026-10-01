package app.storyarc.feature.epubreader

import android.app.NotificationManager
import android.content.Intent
import app.storyarc.core.persistence.SettingsStore
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.android.controller.ServiceController
import org.robolectric.annotation.Config

/**
 * Task 15.5: `ReadAloudService` is a `Context` of its own with no activity above it, so a
 * bare `getString` used to draw its notification channel in the system's language. It now
 * overrides `attachBaseContext` the way `MainActivity` does.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ReadAloudServiceLanguageTest {

    private val context = RuntimeEnvironment.getApplication()
    private var service: ServiceController<ReadAloudService>? = null

    @After
    fun quiet() {
        service?.destroy()
        service = null
    }

    private fun channelName(): String? {
        val controller = Robolectric.buildService(ReadAloudService::class.java, Intent()).create()
        service = controller
        return controller.get().getSystemService(NotificationManager::class.java)
            .getNotificationChannel("read-aloud")?.name?.toString()
    }

    @Test
    fun `the notification channel name follows the chosen language`() {
        val store = SettingsStore.open(context)
        store.save(store.settings().copy(language = "fr"))

        assertEquals("Lecture à voix haute", channelName())
    }

    @Test
    fun `with no language chosen, it reads the same as the bare context`() {
        val store = SettingsStore.open(context)
        store.save(store.settings().copy(language = null))

        assertEquals(context.getString(R.string.readaloud_channel), channelName())
        assertNotEquals("Lecture à voix haute", channelName())
    }
}
