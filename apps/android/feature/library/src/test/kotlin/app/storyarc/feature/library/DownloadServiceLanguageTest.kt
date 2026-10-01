package app.storyarc.feature.library

import android.app.NotificationManager
import app.storyarc.core.persistence.SettingsStore
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.android.controller.ServiceController
import org.robolectric.annotation.Config

/**
 * Task 15.5: `DownloadService` is a `Context` of its own with no activity above it, so a
 * bare `getString` used to draw its notification channel in the system's language. It now
 * overrides `attachBaseContext` the way `MainActivity` does.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class DownloadServiceLanguageTest {

    private val context = RuntimeEnvironment.getApplication()
    private var service: ServiceController<DownloadService>? = null

    @After
    fun quiet() {
        service?.destroy()
        service = null
    }

    private fun channelName(): String? {
        DownloadService.follow(context, 1)
        val started = requireNotNull(shadowOf(context).nextStartedService) {
            "DownloadService.follow started no service, so there is no channel to read."
        }
        val controller = Robolectric.buildService(DownloadService::class.java, started).create()
        service = controller
        controller.startCommand(0, 0)
        return controller.get().getSystemService(NotificationManager::class.java)
            .getNotificationChannel("downloads")?.name?.toString()
    }

    @Test
    fun `the notification channel name follows the chosen language`() {
        val store = SettingsStore.open(context)
        store.save(store.settings().copy(language = "fr"))

        assertEquals("Téléchargements", channelName())
    }

    @Test
    fun `with no language chosen, it reads the same as the bare context`() {
        val store = SettingsStore.open(context)
        store.save(store.settings().copy(language = null))

        assertEquals(context.getString(R.string.downloads_channel), channelName())
        assertNotEquals("Téléchargements", channelName())
    }
}
