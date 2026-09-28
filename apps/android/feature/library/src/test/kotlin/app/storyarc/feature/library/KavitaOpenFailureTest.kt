package app.storyarc.feature.library

import java.io.IOException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Task 21.4: a reading-list entry that could not be fetched used to clear its own spinner and
 * say nothing else, which reads as "a spinner and never opens" exactly as the field report
 * named it. [kavitaOpenFailureTitle] is the one decision behind the sentence
 * [KavitaListScreen] now shows in its place, asserted here because the coroutine that calls it
 * runs inside a `Composable` a plain test cannot reach.
 */
class KavitaOpenFailureTest {

    @Test
    fun `a fetch that failed names the entry`() {
        val outcome = Result.failure<Pair<Nothing, Nothing>>(IOException("no such chapter"))

        assertEquals("Quiet Machines", kavitaOpenFailureTitle("Quiet Machines", outcome))
    }

    @Test
    fun `a fetch that succeeded names nothing`() {
        val outcome = Result.success("ignored")

        assertNull(kavitaOpenFailureTitle("Quiet Machines", outcome))
    }
}
