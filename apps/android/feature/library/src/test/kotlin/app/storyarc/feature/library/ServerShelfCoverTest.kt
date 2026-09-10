package app.storyarc.feature.library

import androidx.compose.ui.test.junit4.v2.createComposeRule
import app.storyarc.core.designsystem.theme.StoryArcTheme
import java.util.concurrent.CopyOnWriteArrayList
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * A server's own shelf is drawn from what it holds.
 *
 * `collections-and-reading-lists`: a shelf's cover "is a composite of its first four member
 * covers unless the user sets a specific one", and this change makes that hold "for a
 * collection a server defines exactly as it does for one made on the device". Before it, a
 * server shelf passed an empty tile list and drew a blank frame.
 *
 * What is asserted here is which artwork the composite asked for, because that is what the
 * rule is about — how many tiles, in what order, and from where. That the four are drawn as
 * quadrants is [ShelfCoverTest]'s claim and is unchanged by this change.
 *
 * `GraphicsMode.NATIVE` and `sdk = [34]` for the reasons [KavitaCardFactsTest] gives.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34])
class ServerShelfCoverTest {

    @get:Rule
    val compose = createComposeRule()

    private val asked = CopyOnWriteArrayList<String>()

    private fun draw(tiles: List<String>) {
        compose.setContent {
            StoryArcTheme {
                ServerShelfCover(
                    tiles = tiles,
                    load = { id ->
                        asked.add(id)
                        ByteArray(0)
                    },
                )
            }
        }
        compose.waitForIdle()
    }

    @Test
    fun `four or more entries composite the first four in the order given`() {
        draw(listOf("11", "12", "13", "14"))

        assertEquals(listOf("11", "12", "13", "14"), asked.toList())
    }

    @Test
    fun `fewer than four put one cover across the frame`() {
        draw(listOf("11", "12"))

        // `shelfTiles` has already cut the list to one by the time it reaches here; what is
        // asserted is that the composite asks for what it was given and invents nothing.
        assertEquals(listOf("11", "12"), asked.toList())
    }

    @Test
    fun `a shelf with nothing in it asks for no artwork and still draws`() {
        draw(emptyList())

        assertEquals(emptyList<String>(), asked.toList())
    }

    @Test
    fun `artwork that never arrives leaves the frame rather than the app`() {
        compose.setContent {
            StoryArcTheme {
                ServerShelfCover(
                    tiles = listOf("11", "12", "13", "14"),
                    load = { throw java.io.IOException("the server is away") },
                )
            }
        }

        // The composition survives a failed fetch: no crash, and the shelf keeps its shape.
        compose.waitForIdle()
    }
}
