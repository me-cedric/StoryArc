package app.storyarc.feature.epubreader

import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import app.storyarc.core.playback.PlaybackService
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * Task 13.2: one media service, so one notification, whichever source speaks.
 *
 * The voice used to run in a foreground service of its own, `ReadAloudService`, which posted a
 * second notification and a second media session. The voice is now a player behind
 * [PlaybackService]'s session, and this module declares no service. The manifest the reader
 * ships with is read here, so a second service added back fails by name.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class OneMediaServiceTest {

    @Test
    fun `the player's media service is the only media service the reader ships with`() {
        val context = RuntimeEnvironment.getApplication()

        val media = context.packageManager
            .getPackageInfo(context.packageName, PackageManager.GET_SERVICES)
            .services.orEmpty()
            .filter { it.foregroundServiceType and ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK != 0 }
            .map { it.name }

        assertEquals(listOf(PlaybackService::class.java.name), media)
    }
}
