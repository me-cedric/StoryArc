package app.storyarc.feature.library

import androidx.compose.foundation.layout.height
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.unit.dp
import java.util.concurrent.CopyOnWriteArrayList
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * A long list asks the server only for the rows a reader has reached.
 *
 * design.md: the cover is fetched "inside the row composable keyed by `chapterId`, as the
 * series grid does, so only visible rows fetch". Seventy-seven entries is the length of the
 * list this change was found on, and seventy-seven cover requests on open is what the
 * decision exists to prevent.
 *
 * `GraphicsMode.NATIVE` and `sdk = [34]` for the reasons [KavitaCardFactsTest] gives.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34])
class ServerListCoverFetchTest {

    @get:Rule
    val compose = createComposeRule()

    @Test
    fun `a row that was never composed is never fetched`() {
        val asked = CopyOnWriteArrayList<Int>()

        compose.setContent {
            LazyColumn(modifier = Modifier.height(200.dp)) {
                items((1..77).toList()) { id ->
                    // The value is unused: what is under test is who was asked.
                    rememberChapterCover(id) { chapterId ->
                        asked.add(chapterId)
                        ByteArray(0)
                    }
                    androidx.compose.foundation.layout.Spacer(Modifier.height(56.dp))
                }
            }
        }
        compose.waitForIdle()

        assertTrue(
            "A 200 dp window over 56 dp rows cannot have reached row 77. Asked: $asked",
            asked.size < 20,
        )
        assertTrue("The first row is on screen and must have been asked.", 1 in asked)
        assertTrue("The last row is far below and must not have been.", 77 !in asked)
    }

    @Test
    fun `one chapter is asked for once, however often the row recomposes`() {
        val asked = CopyOnWriteArrayList<Int>()

        compose.setContent {
            rememberChapterCover(3103) { id ->
                asked.add(id)
                ByteArray(0)
            }
        }
        compose.waitForIdle()

        assertTrue("Asked ${asked.size} times: $asked", asked.size == 1)
    }
}
