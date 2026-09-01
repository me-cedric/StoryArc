package app.storyarc.feature.settings

import android.content.Context
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Book
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.util.UUID

/**
 * When the app tells a reader what changed, and when it says nothing at all.
 *
 * `settings-and-about`: the screen is shown "once per version", "does not appear" on a first
 * ever launch, and a version with nothing worth saying "is still recorded as seen, so the
 * entry is not shown late alongside the next one".
 *
 * Four scenarios, one rule: **the version is recorded at the moment the decision is taken**,
 * whichever way the decision goes. That is what makes the two silent branches safe, and it
 * is also the spec's clause about dismissal — "the seen flag is written when the screen is
 * shown, not when it is dismissed" — because a reader who swipes the sheet away has still
 * seen it, and nothing here is waiting for them to press anything.
 *
 * Robolectric because the store is `SharedPreferences` and `testDebugUnitTest` has no device
 * to open one on. The alternative was an interface with a map behind it in the test, which
 * would assert that the fake works.
 *
 * Mirrored case for case by `WhatsNewTests.swift`.
 */
@RunWith(RobolectricTestRunner::class)
// Robolectric ships no image for API 37, and nothing here has an API level in it.
@Config(sdk = [34])
class WhatsNewTest {

    /** A preferences file of its own, so one test cannot read what another wrote. */
    private fun store(): WhatsNewStore {
        val context = ApplicationProvider.getApplicationContext<Context>()
        return WhatsNewStore(
            context.getSharedPreferences("whatsnew-${UUID.randomUUID()}", Context.MODE_PRIVATE),
        )
    }

    /** A log with one release in it, so the assertions do not move when the shipped log does. */
    private val log = listOf(
        WhatsNewRelease(
            version = "0.2.0",
            notes = listOf(
                WhatsNewNote(
                    icon = Icons.Filled.Book,
                    title = R.string.about_version,
                    body = R.string.about_author,
                ),
            ),
        ),
    )

    @Test
    fun `a first ever launch shows nothing, and records the version anyway`() {
        val store = store()
        assertNull(store.seenVersion())

        val shown = WhatsNew.onLaunch(installed = "0.2.0", store = store, releases = log)

        assertNull("Somebody who has never used the app has nothing to catch up on", shown)
        assertEquals(
            "The version is recorded even so, so the next update is the first thing they are told about",
            "0.2.0",
            store.seenVersion(),
        )
    }

    @Test
    fun `an update shows the release once`() {
        val store = store()
        store.record("0.1.0")

        val first = WhatsNew.onLaunch(installed = "0.2.0", store = store, releases = log)
        assertEquals("0.2.0", first?.version)

        val second = WhatsNew.onLaunch(installed = "0.2.0", store = store, releases = log)
        assertNull("Shown once per version, not once per launch", second)
    }

    @Test
    fun `a second launch at the same version shows nothing`() {
        val store = store()
        store.record("0.2.0")

        assertNull(WhatsNew.onLaunch(installed = "0.2.0", store = store, releases = log))
    }

    @Test
    fun `a version with nothing to say shows nothing and is still recorded`() {
        val store = store()
        store.record("0.2.0")

        val shown = WhatsNew.onLaunch(installed = "0.3.0", store = store, releases = log)

        assertNull("0.3.0 has no entry in this log", shown)
        assertEquals(
            "Recorded regardless, or 0.3.0's entry arrives late beside 0.4.0's",
            "0.3.0",
            store.seenVersion(),
        )
    }

    @Test
    fun `reaching the log from About changes nothing about what is seen`() {
        val store = store()
        store.record("0.1.0")

        // What About shows is the whole log, and the log is a value with no store behind it
        // — reading it cannot write. This half only proves the reading is possible; the half a
        // mutation can break is `app.storyarc.WhatsNewWiringTest`, in `:app`, which asserts
        // that no source in this module names `WhatsNewStore`.
        //
        // **That file did not exist when this comment first named it**, and the gap was exactly
        // the shape the comment described: handing `WhatsNewHistory` a store left every Android
        // gate green. It is in `:app` rather than beside this file because the other two claims
        // it makes are about `AppShell`, which lives there.
        assertFalse(WhatsNew.releases.isEmpty())
        assertEquals("0.1.0", store.seenVersion())
    }

    /**
     * The ordering assertion below cannot fail while the log holds one release, so the
     * comparator it uses is pinned here on fixtures instead. `0.10.0` against `0.9.0` is the
     * case a string comparison gets wrong, and About lists these to a reader.
     */
    @Test
    fun `a version is newer by its numbers, not by its letters`() {
        assertTrue(WhatsNew.isNewer("0.10.0", "0.9.0"))
        assertTrue(WhatsNew.isNewer("1.0.0", "0.99.9"))
        assertTrue(WhatsNew.isNewer("0.2.1", "0.2.0"))
        assertFalse(WhatsNew.isNewer("0.2.0", "0.2.0"))
        assertFalse(WhatsNew.isNewer("0.9.0", "0.10.0"))
        // A shorter string is not automatically older: 0.2 and 0.2.0 are the same version.
        assertFalse(WhatsNew.isNewer("0.2", "0.2.0"))
        assertTrue(WhatsNew.isNewer("0.2.1", "0.2"))
    }

    @Test
    fun `the shipped log names releases newest first, and each version once`() {
        val versions = WhatsNew.releases.map { it.version }
        assertEquals("A version appears twice: $versions", versions.size, versions.toSet().size)
        val newestFirst = versions.sortedWith { a, b ->
            when {
                a == b -> 0
                WhatsNew.isNewer(a, b) -> -1
                else -> 1
            }
        }
        assertEquals("About lists these in order, newest first", newestFirst, versions)
    }

    /**
     * A release with no notes would present an empty sheet, and two notes sharing a title
     * would give the row list a duplicate key — one row drawn, the other silently gone.
     */
    @Test
    fun `every shipped release has notes, each under its own heading`() {
        for (release in WhatsNew.releases) {
            assertFalse("${release.version} has an empty note list", release.notes.isEmpty())
            val titles = release.notes.map { it.title }
            assertEquals(
                "${release.version} repeats a heading: $titles",
                titles.size,
                titles.toSet().size,
            )
        }
    }

    /** The screen is a handful of rows, not a commit log. Apple's own runs to four or five. */
    @Test
    fun `no shipped release is a wall of text`() {
        for (release in WhatsNew.releases) {
            assertTrue(
                "${release.version} lists ${release.notes.size} notes",
                release.notes.size <= 5,
            )
        }
    }
}
