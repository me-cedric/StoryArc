package app.storyarc

import android.content.ComponentName
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import androidx.test.platform.app.InstrumentationRegistry
import app.storyarc.core.playback.PlaybackService
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The player's platform contract, asked of the **installed package**.
 *
 * `audio-playback` asks that playback outlive the publication and that the system's own
 * controls drive the same session. On Android neither is a thing the app can do by trying:
 * without a foreground service of type `mediaPlayback` the process is frozen the moment the
 * listener leaves the app, and without the two permissions the service cannot declare that
 * type at all from API 34.
 *
 * **Asked of the `PackageManager` rather than of a file**, which is the point of it being
 * an instrumented test. A source guard over `core/playback/src/main/AndroidManifest.xml`
 * would pass with the app not depending on the module at all, and the manifest merger is
 * exactly where that mistake lands. What the system will actually honour is what the system
 * has actually installed, and this asks it.
 *
 * Nothing here starts the service or plays a sound. It is a declaration test, and it runs in
 * a second.
 */
class PlayerServiceIsDeclaredTest {

    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val packages: PackageManager get() = context.packageManager

    private val service: ServiceInfo
        get() {
            val component = ComponentName(context, PlaybackService::class.java)
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packages.getServiceInfo(
                    component,
                    PackageManager.ComponentInfoFlags.of(0L),
                )
            } else {
                @Suppress("DEPRECATION")
                packages.getServiceInfo(component, 0)
            }
        }

    @Test
    fun `the player service is in the merged manifest`() {
        // `getServiceInfo` throws `NameNotFoundException` when it is not, which is the
        // failure — the assertion is that this line returns at all.
        assertEquals(PlaybackService::class.java.name, service.name)
    }

    @Test
    fun `the service declares media playback as its foreground type`() {
        // Required since API 34: a service may only start in the foreground under a type
        // the manifest declared, and `mediaPlayback` is the only one that keeps audio
        // running once the listener has left the app.
        assertTrue(
            "the service declares no mediaPlayback foreground type, so it cannot keep a" +
                " book playing once the app is in the background",
            service.foregroundServiceType and ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK != 0,
        )
    }

    @Test
    fun `the app asks for both foreground-service permissions`() {
        // The other half of the API 34 rule: a service may only declare a type the *app*
        // has asked for, so the type above is inert without these two.
        val requested = packages
            .getPackageInfo(context.packageName, PackageManager.GET_PERMISSIONS)
            .requestedPermissions
            ?.toSet()
            .orEmpty()

        for (permission in listOf(
            android.Manifest.permission.FOREGROUND_SERVICE,
            android.Manifest.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK,
        )) {
            assertTrue("$permission is not requested", permission in requested)
        }
    }

    @Test
    fun `the service answers the session and the browser actions`() {
        // What binds to it. `MediaSessionService` is the shade, the lock screen and the
        // app's own controller; `MediaBrowserService` is the legacy action a car and Wear
        // still send, and a service answering only the first is invisible to them.
        //
        // Resolved by intent rather than read off the component, because being *declared*
        // and being *reachable* are different facts and only the second is the one that
        // matters to a head unit.
        for (action in listOf(
            "androidx.media3.session.MediaSessionService",
            "android.media.browse.MediaBrowserService",
        )) {
            val matches = packages.queryIntentServices(
                android.content.Intent(action).setPackage(context.packageName),
                0,
            )
            assertTrue(
                "nothing in the package answers $action",
                matches.any { it.serviceInfo.name == PlaybackService::class.java.name },
            )
        }
    }

    @Test
    fun `the app declares itself drivable from a car`() {
        // `automotive_app_desc.xml`, reached the way a head unit reaches it: the
        // `com.google.android.gms.car.application` meta-data on the application. An
        // audiobook player that cannot be driven from a car is missing its best use, and
        // the declaration is the whole of what makes it appear there.
        val application = packages
            .getApplicationInfo(context.packageName, PackageManager.GET_META_DATA)
        val resource = application.metaData?.getInt("com.google.android.gms.car.application") ?: 0
        assertTrue("the automotive descriptor is not declared", resource != 0)
    }
}
