package app.storyarc.core.persistence

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Before
import org.junit.Test
import org.junit.Assert.assertEquals
import org.junit.runner.RunWith

/**
 * What the app remembers about how fast a listener wants a book read.
 *
 * `audio-playback`: the speed "is remembered for that publication and offered as the default
 * for others in the same series".
 *
 * Instrumented because `SharedPreferences` is a framework component, like every other store
 * in this module.
 */
@RunWith(AndroidJUnit4::class)
class PlaybackPreferencesTest {

    private fun preferences() = PlaybackPreferences.open(
        InstrumentationRegistry.getInstrumentation().context,
    )

    @Before
    fun clean() {
        preferences().clear()
    }

    @Test
    fun aPublicationNobodyHasSetStartsAtTheNarratorsOwnSpeed() {
        assertEquals(1.0, preferences().speed("sea-room", "Sea Room"), 0.0)
    }

    @Test
    fun aSpeedComesBackForThePublicationItWasSetOn() {
        val preferences = preferences()
        preferences.rememberSpeed("sea-room-1", "Sea Room", 1.4)

        assertEquals(1.4, preferences.speed("sea-room-1", "Sea Room"), 0.001)
    }

    @Test
    fun theRestOfTheSeriesIsOfferedIt() {
        val preferences = preferences()
        preferences.rememberSpeed("sea-room-1", "Sea Room", 1.4)

        assertEquals(1.4, preferences.speed("sea-room-2", "Sea Room"), 0.001)
    }

    /**
     * The publication's own choice wins, and adjusting one book does not reach back.
     *
     * The series entry is a *default*, which is what the requirement calls it: a listener
     * who slows volume two down has said something about volume two.
     */
    @Test
    fun aPublicationsOwnSpeedWinsOverTheSeriesDefault() {
        val preferences = preferences()
        preferences.rememberSpeed("sea-room-1", "Sea Room", 1.4)
        preferences.rememberSpeed("sea-room-2", "Sea Room", 0.9)

        assertEquals(1.4, preferences.speed("sea-room-1", "Sea Room"), 0.001)
        assertEquals(0.9, preferences.speed("sea-room-2", "Sea Room"), 0.001)
    }

    @Test
    fun anotherSeriesIsNotOfferedIt() {
        val preferences = preferences()
        preferences.rememberSpeed("sea-room-1", "Sea Room", 1.4)

        assertEquals(1.0, preferences.speed("another", "Somewhere Else"), 0.0)
    }

    /** A publication belonging to no series still remembers its own. */
    @Test
    fun aPublicationWithNoSeriesRemembersItsOwn() {
        val preferences = preferences()
        preferences.rememberSpeed("standalone", null, 2.0)

        assertEquals(2.0, preferences.speed("standalone", null), 0.001)
        assertEquals(1.0, preferences.speed("other", null), 0.0)
    }

    @Test
    fun clearingForgetsEverything() {
        val preferences = preferences()
        preferences.rememberSpeed("sea-room-1", "Sea Room", 1.4)

        preferences.clear()

        assertEquals(1.0, preferences.speed("sea-room-1", "Sea Room"), 0.0)
        assertEquals(1.0, preferences.speed("sea-room-2", "Sea Room"), 0.0)
    }
}
