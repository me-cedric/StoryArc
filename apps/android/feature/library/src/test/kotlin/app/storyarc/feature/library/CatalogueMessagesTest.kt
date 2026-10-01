package app.storyarc.feature.library

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.catalogue.OpdsError
import java.io.IOException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Task 15.2: a malformed feed's parser reason, and a transport failure's raw exception
 * message, must never reach the reader. Both are logged instead of drawn.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class CatalogueMessagesTest {

    private val context: Application get() = ApplicationProvider.getApplicationContext()

    @Test
    fun aMalformedFeedNeverShowsTheParserReason() {
        val reason = "Expected BEGIN_OBJECT but was STRING at line 1 column 1"
        val sentence = CatalogueMessages.describe(context, OpdsError.Malformed(reason))

        assertFalse("parser reason leaked into: $sentence", sentence.contains(reason))
        assertEquals("The catalogue could not be read.", sentence)
    }

    @Test
    fun anUnrecognisedTransportFailureShowsTheFixedUnreachableSentence() {
        val raw = IOException("Unable to resolve host \"example.invalid\": No address associated with hostname")
        val sentence = CatalogueMessages.reachability(context, raw)

        assertFalse("raw exception text leaked into: $sentence", sentence.contains("No address associated"))
        assertEquals("This server could not be reached.", sentence)
    }
}
