package app.storyarc.feature.settings

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * The acknowledgements list ships with the app, and it is not empty.
 *
 * `settings-and-about`, *Acknowledgements*: "every third-party library is listed with its
 * licence text". [Notices.forAndroid] reads a staged asset and answers an empty list on any
 * failure, so a staging task that stops running, a renamed asset path or a malformed
 * inventory all produce a screen with a heading and no rows. That is a licence breach, and
 * before this suite no gate could see it: `pnpm notices:check` compares the inventory with
 * `THIRD_PARTY_NOTICES.md` in the repository and never asks whether the binary carries it.
 *
 * Robolectric rather than a plain JVM test, because the inventory reaches the app through
 * the merged assets and only a real [Context] has those. iOS reads the same inventory
 * through `StoryArcLicences`, and that path has no test suite yet.
 */
@RunWith(RobolectricTestRunner::class)
// Robolectric ships no image for API 37, and nothing here has an API level in it.
@Config(sdk = [34])
class AcknowledgementsTest {

    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private val notices get() = Notices.forAndroid(context.assets)

    @Test
    fun `the inventory reaches the app rather than staying in the repository`() {
        assertTrue(
            "The app ships no acknowledgements at all. The licence inventory did not reach" +
                " the assets, so the About screen draws a heading over nothing.",
            notices.isNotEmpty(),
        )
    }

    @Test
    fun `every listed component ships the licence text it names`() {
        notices.forEach { notice ->
            val text = Notices.text(context.assets, notice)
            assertTrue(
                "${notice.name} names the ${notice.licence} licence and this build carries no" +
                    " text for it, so its row opens on a packaging-bug message.",
                !text.isNullOrBlank(),
            )
        }
    }

    @Test
    fun `the list holds this platform's components and not the other app's`() {
        // Filtering is the reason an empty list is plausible at all: a filter that matched
        // nothing would look exactly like an inventory that failed to load.
        assertTrue(
            "No listed component names Android, so the platform filter matched nothing.",
            notices.any { it.platforms.contains("android") },
        )
        notices.forEach { notice ->
            assertTrue(
                "${notice.name} is the other app's: it declares ${notice.platforms}.",
                notice.platforms.isEmpty() || notice.platforms.contains("android"),
            )
        }
    }

    @Test
    fun `every listed component states why it is here`() {
        // `settings-and-about` asks the screen to make the inventory visible; `Notice.why`
        // is the field that makes a dependency nobody can justify visible with it.
        notices.forEach { notice ->
            assertTrue("${notice.name} has no name", notice.name.isNotBlank())
            assertTrue("${notice.name} states no reason", notice.why.isNotBlank())
            assertTrue("${notice.name} names no licence", notice.licence.isNotBlank())
        }
    }
}
