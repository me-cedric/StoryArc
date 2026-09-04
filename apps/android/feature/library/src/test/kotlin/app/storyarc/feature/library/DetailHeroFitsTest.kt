package app.storyarc.feature.library

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * At 800 × 360 dp there was no way to start the book from its own page.
 *
 * The primary action sat 112 dp below the fold at rest and 24 dp below it after the app bar
 * had collapsed as far as Material lets it, with the hero's wash filling the whole 96 dp
 * strip so nothing said there was anything under it. `DetailHeroLayoutTest` asserts the
 * arithmetic; this asserts that the composition it produces actually puts the button on
 * screen, inside the room the page has and with nothing scrolled.
 *
 * `GraphicsMode.NATIVE` for the reason `ListOrderChipsWrapTest` gives: legacy graphics
 * measure a glyph at about a pixel wide, so a control drawn off the window still passes.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w800dp-h360dp")
class DetailHeroFitsTest {

    @get:Rule
    val compose = createComposeRule()

    private val book = Publication(
        identity = PublicationIdentity(contentDigest = "broken-transfer"),
        format = PublicationFormat.CBZ,
        displayTitle = "Broken Transfer",
        origin = MetadataOrigin.INFERRED,
    )

    private val onDevice = Provenance(
        place = Provenance.Place.DEVICE,
        libraryName = null,
        readiness = Provenance.Readiness.READY,
        isAlsoElsewhere = false,
    )

    /** The room a landscape phone leaves: 360 dp, less status bar, short app bar and nav bar. */
    private val room = 184.dp

    @Test
    fun theActionIsOnScreenOnALandscapePhone() {
        compose.setContent {
            StoryArcTheme {
                Box(modifier = Modifier.fillMaxWidth().height(room)) {
                    DetailMainPane(
                        publication = book,
                        cover = null,
                        accent = null,
                        hero = DetailHeroLayout.of(windowHeight = 360.dp, room = room),
                        action = PrimaryAction.READ,
                        provenance = onDevice,
                        downloadFraction = null,
                        onRead = {},
                        onDownload = null,
                    )
                }
            }
        }

        // Displayed, not merely present: the defect was a button that existed in the tree
        // and was not on the screen.
        compose.onNodeWithText("Read").assertIsDisplayed()
    }

    @Test
    fun theHeroDoesNotOutgrowTheRoomItWasGiven() {
        compose.setContent {
            StoryArcTheme {
                Box(modifier = Modifier.fillMaxWidth().height(room)) {
                    DetailHero(
                        publication = book,
                        cover = null,
                        accent = null,
                        layout = DetailHeroLayout.of(windowHeight = 360.dp, room = room),
                        modifier = Modifier.testTag(HERO),
                        action = {},
                    )
                }
            }
        }

        val hero = compose.onNodeWithTag(HERO).fetchSemanticsNode().size.height
        val allowed = with(compose.density) { room.roundToPx() }
        assert(hero <= allowed) { "the hero is $hero px inside $allowed px of room" }
    }

    private companion object {
        const val HERO = "detail-hero"
    }
}
