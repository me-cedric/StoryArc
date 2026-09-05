package app.storyarc.feature.settings

import android.content.ComponentName
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.shadows.ShadowApplicationPackageManager

/**
 * A package manager that can be told to refuse a component write.
 *
 * Robolectric's own shadow accepts every `setComponentEnabledSetting`, so the path
 * `settings-and-about` specifies as "the platform declines the change" cannot be reached
 * through it. `AppIconSwitcherTest` reaches that path by injecting a throwing `write`;
 * `AppIconGroup` builds its switcher from the context's own package manager and has no seam,
 * which is right for a settings row and leaves this as the way to compose the real group over
 * a refusing device. Registered per test with `@Config(shadows = [...])`, which is how a custom
 * shadow takes the framework one's place.
 *
 * Reads are untouched: `applied()` still answers from the component states this shadow's
 * parent keeps, so a test can disable every alias first and then refuse the press that would
 * recover — the one state `AppIconGroup` has a sentence of its own for.
 */
@Implements(className = "android.app.ApplicationPackageManager", isInAndroidSdk = false)
class RefusingPackageManager : ShadowApplicationPackageManager() {

    @Implementation
    override fun setComponentEnabledSetting(componentName: ComponentName, newState: Int, flags: Int) {
        if (refuses) throw SecurityException("the platform said no")
        super.setComponentEnabledSetting(componentName, newState, flags)
    }

    companion object {
        /** Whether the next write is refused. Every test that sets it puts it back. */
        @JvmStatic
        var refuses: Boolean = false
    }
}
