package app.storyarc.feature.library

import app.storyarc.core.model.PublicationFormat
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * That a refusal of an unsupported container states what StoryArc reads instead.
 *
 * `publication-formats`: the app "states which formats it does support" and "never reports a
 * generic failure". The share browser's sentence for a typed index refusal and the shelf's
 * sentence for a CB7 row both said less than that. Lint already fails a sentence missing from
 * one of the four languages, so this reads the English one only.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class RefusalWordingTest {

    private fun english(resource: Int): String = RuntimeEnvironment.getApplication().getString(resource)

    @Test
    fun `the share browser's unsupported sentence lists the formats StoryArc reads`() {
        val sentence = english(UNSUPPORTED)
        assertTrue("$sentence names no format StoryArc reads.", sentence.contains("CBZ"))
    }

    @Test
    fun `a cb7 row names its container, not solid compression`() {
        val sentence = english(refusalSentence(PublicationFormat.CB7))
        assertTrue("$sentence does not name CB7.", sentence.contains("CB7"))
        assertTrue("$sentence names no format StoryArc reads.", sentence.contains("CBZ"))
        assertFalse("$sentence blames solid compression.", sentence.contains("solid"))
    }
}
