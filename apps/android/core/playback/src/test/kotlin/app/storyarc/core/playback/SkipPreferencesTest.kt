package app.storyarc.core.playback

import android.content.Context
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * The listener's own skip intervals, kept where the service can read them.
 *
 * `audio-playback` asks for an interval "the listener can configure", which is what makes
 * this a store rather than two constants. It lives beside [PlaybackMemory] and not in
 * `:core:persistence` for [PlaybackMemory]'s own reason: `PlaybackService` sets the
 * decoder's increments and labels the notification's two outer buttons, and a service the
 * system has just started has no scope and no database — and `:core:playback` deliberately
 * does not depend on the library's.
 *
 * Robolectric because `SharedPreferences` is a framework component. Nothing here decodes.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SkipPreferencesTest {

    private fun preferences() = SkipPreferences.open(RuntimeEnvironment.getApplication())

    /** Two ints into the file, the way an older build with no type between them would. */
    private fun write(backSeconds: Int, forwardSeconds: Int) {
        RuntimeEnvironment.getApplication()
            .getSharedPreferences(SkipPreferences.FILE, Context.MODE_PRIVATE)
            .edit()
            .putInt(SkipPreferences.BACK_SECONDS, backSeconds)
            .putInt(SkipPreferences.FORWARD_SECONDS, forwardSeconds)
            .apply()
    }

    @Before
    fun clear() {
        preferences().forget()
    }

    @Test
    fun `a device that has never been asked answers the defaults`() {
        assertEquals(SkipIntervals.DEFAULT, preferences().intervals())
    }

    @Test
    fun `what the listener chose is what comes back`() {
        preferences().remember(SkipIntervals.of(backSeconds = 10, forwardSeconds = 5))

        // A second instance, because the point is the file rather than the object.
        assertEquals(SkipIntervals.of(10, 5), preferences().intervals())
    }

    /**
     * A stored pair from another build still plays, at the nearest interval that works.
     *
     * `PlaybackSpeed`'s rule, applied here: a store is not where a range is validated, and a
     * value read back outside it is clamped rather than thrown away — losing the listener's
     * setting silently is the worse of the two.
     */
    @Test
    fun `a stored interval outside the range comes back clamped`() {
        write(backSeconds = 600, forwardSeconds = 2)

        assertEquals(30, preferences().intervals().backSeconds)
        assertEquals(5, preferences().intervals().forwardSeconds)
    }

    /**
     * A stored zero is not believed, and this is the one dangerous case.
     *
     * `SharedPreferences` answers the default it is handed for a key it has never seen, and
     * there is no sentinel to pass — so zero means "unset" and it is also the one interval a
     * skip may never have, a control that moves nothing. Believing it would give a listener
     * who never touched the setting two buttons that do nothing. iOS's own
     * `PlaybackPreferences` records the identical hazard for `UserDefaults` and a speed of
     * zero.
     */
    @Test
    fun `a stored zero is read as unset rather than as an interval`() {
        write(backSeconds = 0, forwardSeconds = 0)

        assertEquals(SkipIntervals.DEFAULT, preferences().intervals())
    }

    @Test
    fun `forgetting puts the defaults back`() {
        preferences().remember(SkipIntervals.of(5, 5))
        preferences().forget()

        assertEquals(SkipIntervals.DEFAULT, preferences().intervals())
    }
}
