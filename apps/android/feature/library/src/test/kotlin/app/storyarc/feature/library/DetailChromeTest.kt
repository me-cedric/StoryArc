package app.storyarc.feature.library

import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.CoverColours
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The cover's colour reaches the page and never reaches Material's scheme.
 *
 * This is task 0.2's deliverable — "a test that chrome colour is unchanged when an accent is
 * set" — and until it existed the separation was asserted only structurally: by
 * `Theme.groundedInContent` pinning three roles, and by the accent never being handed to
 * `MaterialTheme`. That is an argument, and an argument does not fail when somebody wraps
 * this page in `MaterialTheme(colorScheme = …)`.
 *
 * **Why that is the shape the defect would take.** Wrapping a subtree in a second
 * `MaterialTheme` is Compose's own idiom for giving part of a tree a different colour, so it
 * is the first thing anyone reaches for when asked to make the page belong to the book. It
 * would tint every Material component *inside* the subtree — the app bar's overflow, a
 * dropdown, a dialog, the download progress — which is exactly what `publication-detail`
 * forbids: the derived colour "reaches the page's content surfaces only", and chrome must
 * not "change hue as a reader moves between publications". [DetailAccent] travels **beside**
 * the scheme rather than in it, and this is the assertion that keeps it there.
 *
 * **The scheme is compared by identity as well as role by role.** `ColorScheme` does not
 * override `equals`, so a role-by-role comparison is the readable half and `assertSame` is
 * the exhaustive one: a re-provided scheme is a different instance whatever its values are.
 *
 * **And the accent is proved live, in the same file.** A test that only asserts an absence
 * passes just as well when the accent is ignored altogether, which would make it vacuous in
 * the way `AGENTS.md` §5 warns about. [theAccentDoesReachTheContent] lets a cover land on the
 * same hero and compares the pixels either side of it, so "the chrome did not move" means
 * something.
 *
 * `GraphicsMode.NATIVE` for `ListOrderChipsWrapTest`'s reason, and because a pixel
 * comparison under Robolectric's legacy graphics compares nothing.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
// Robolectric ships an image per API level and has none for 37, so it cannot be handed the
// module's target. 34 is inside its range and above the minimum this app supports.
@Config(sdk = [34], qualifiers = "w411dp-h891dp")
class DetailChromeTest {

    @get:Rule
    val compose = createComposeRule()

    private val book = Publication(
        identity = PublicationIdentity(contentDigest = "p1"),
        format = PublicationFormat.CBZ,
        displayTitle = "The Harbour",
        series = "Tidal Reach",
        origin = MetadataOrigin.AUTHORITATIVE,
    )

    /** A vivid accent, so anything it tinted would be obvious rather than marginal. */
    private val accent = detailAccentOf(
        CoverColours(wash = "#1A0E22", accent = "#EC7C27", onAccent = "#000000"),
    )

    private val layout = DetailHeroLayout(isSideBySide = false, coverHeight = 160.dp)

    @Test
    fun `an accent set on the hero leaves the scheme its own subtree reads untouched`() {
        assertNotNull("the fixture's own accent failed to parse", accent)
        var outside: ColorScheme? = null
        var inside: ColorScheme? = null

        compose.setContent {
            StoryArcTheme {
                outside = MaterialTheme.colorScheme
                DetailHero(
                    publication = book,
                    cover = null,
                    accent = accent,
                    layout = layout,
                ) {
                    // The action slot is inside the `Surface` the wash is painted on, so this
                    // is the scheme a Material component drawn by this page would read.
                    inside = MaterialTheme.colorScheme
                    Text("action")
                }
            }
        }
        compose.waitForIdle()

        val ambient = requireNotNull(outside)
        val page = requireNotNull(inside)
        for ((role, colour) in ambient.chromeRoles()) {
            assertEquals("$role moved inside the page", colour, page.chromeRoles()[role])
        }
        // Exhaustive where the loop above is readable: a second `MaterialTheme` is a
        // different instance whatever it was given.
        assertSame("the page re-provided Material's scheme", ambient, page)
    }

    @Test
    fun theAccentDoesReachTheContent() {
        // The other half, and the one that stops the assertion above from being vacuous. If
        // `DetailHero` ignored its accent the chrome test would pass for the wrong reason.
        //
        // One composition with the accent as state, rather than two `setContent` calls: a
        // compose rule accepts content exactly once, and swapping the state is also the
        // truer fixture — it is the arrival the page actually performs when a cover lands.
        val state = mutableStateOf<DetailAccent?>(null)
        compose.setContent {
            StoryArcTheme {
                DetailHero(
                    publication = book,
                    cover = null,
                    accent = state.value,
                    layout = layout,
                ) { Text("action") }
            }
        }
        compose.waitForIdle()
        val plain = compose.onRoot().captureToImage().toPixelMap()
        state.value = accent
        compose.waitForIdle()
        val washed = compose.onRoot().captureToImage().toPixelMap()

        assertEquals("the two renders are different sizes", plain.width, washed.width)
        assertEquals("the two renders are different sizes", plain.height, washed.height)
        var differing = 0
        for (y in 0 until plain.height) {
            for (x in 0 until plain.width) {
                if (plain[x, y] != washed[x, y]) differing += 1
            }
        }
        // The wash is the hero's whole ground, so a real accent moves most of the frame. A
        // tenth is far above anti-aliasing noise and far below what an accent that arrived
        // actually changes.
        val total = plain.width * plain.height
        assertTrue(
            "only $differing of $total pixels moved: the accent did not reach the hero",
            differing > total / 10,
        )
    }
}

/**
 * The roles a Material component drawn on this page would take its colour from.
 *
 * Not every role in the scheme: the point is a readable failure naming the role that moved,
 * and `assertSame` beside it already covers the rest. These are the ones an app bar, an
 * overflow, a dialog, a sheet and a filled button actually read.
 */
private fun ColorScheme.chromeRoles(): Map<String, Color> = mapOf(
    "primary" to primary,
    "onPrimary" to onPrimary,
    "primaryContainer" to primaryContainer,
    "secondary" to secondary,
    "surface" to surface,
    "onSurface" to onSurface,
    "surfaceVariant" to surfaceVariant,
    "surfaceContainer" to surfaceContainer,
    "surfaceContainerHigh" to surfaceContainerHigh,
    "background" to background,
    "onBackground" to onBackground,
    "outline" to outline,
)
