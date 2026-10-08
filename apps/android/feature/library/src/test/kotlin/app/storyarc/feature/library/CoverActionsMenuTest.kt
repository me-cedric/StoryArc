package app.storyarc.feature.library

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.StoryArcTheme
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Task 24.1, 24.2 and 24.5 of `close-the-audited-gaps`: a cover's actions are one menu, every
 * target of it is at least 48 dp, and removing asks first.
 *
 * The owner found three text buttons stacked with no space between them, each as tall as its
 * text, and a finger hit the wrong one. Material 3 asks for a touch target of 48 x 48 dp.
 * These tests measure the real semantics nodes, so an edit that shrinks a target fails here
 * rather than on a phone. iOS's `CoverMenuTests` is the twin.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w411dp-h891dp")
class CoverActionsMenuTest {

    @get:Rule
    val compose = createComposeRule()

    private val all = CoverMenu({}, {}, {}, {}, {})

    // The rule, on its own.

    @Test
    fun `every way of setting a cover is one group and removal is last, alone`() {
        assertEquals(
            listOf(
                listOf(CoverAction.CHOOSE, CoverAction.FIND, CoverAction.WEB, CoverAction.SEND),
                listOf(CoverAction.REMOVE),
            ),
            all.groups(),
        )
    }

    @Test
    fun `a row without a handler is not drawn and an empty group leaves no divider`() {
        assertEquals(listOf(listOf(CoverAction.CHOOSE)), CoverMenu(onChoose = {}).groups())
        assertEquals(
            listOf(listOf(CoverAction.CHOOSE, CoverAction.WEB), listOf(CoverAction.REMOVE)),
            CoverMenu(onChoose = {}, onWeb = {}, onRemove = {}).groups(),
        )
        assertEquals(emptyList<List<CoverAction>>(), CoverMenu().groups())
    }

    @Test
    fun `the page offers the title search only while the lookup is on`() {
        val finder = { on: Boolean ->
            CoverFinder(CoverFinderOffer.of(on), "Fine Print", "Ada", onFind = {}, onOpenWeb = {})
        }

        assertEquals(
            listOf(listOf(CoverAction.CHOOSE, CoverAction.WEB)),
            CoverChoice(onChoose = {}, finder = finder(false)).menu().groups(),
        )
        assertEquals(
            listOf(listOf(CoverAction.CHOOSE, CoverAction.FIND, CoverAction.WEB)),
            CoverChoice(onChoose = {}, finder = finder(true)).menu().groups(),
        )
    }

    @Test
    fun `a page that offers no choice draws no menu`() {
        assertEquals(emptyList<List<CoverAction>>(), CoverChoice.unavailable.menu().groups())
        assertEquals(
            emptyList<List<CoverAction>>(),
            CoverChoice(onRemove = {}).menu(onSend = {}).groups(),
        )
    }

    // The menu, drawn.

    private fun show(menu: CoverMenu = all, scale: Float = 1f) {
        compose.setContent {
            StoryArcTheme {
                val density = LocalDensity.current
                CompositionLocalProvider(
                    LocalDensity provides Density(density.density, fontScale = scale),
                ) {
                    var open by remember { mutableStateOf(false) }
                    CoverActionsHost(
                        menu = menu,
                        open = open,
                        onOpenChange = { open = it },
                        accent = null,
                    ) {
                        Box(Modifier.size(96.dp, 144.dp))
                    }
                }
            }
        }
        compose.waitForIdle()
    }

    private fun openMenu() {
        compose.onNodeWithContentDescription(EDIT).performClick()
        compose.waitForIdle()
    }

    @Test
    fun `the edit button has a touch target of 48 dp`() {
        show()

        compose.onNodeWithContentDescription(EDIT)
            .assertTouchTargetIsAtLeast()
    }

    @Test
    fun `every row of the menu has a touch target of 48 dp`() {
        show()
        openMenu()

        for (row in ROWS) {
            compose.onNodeWithText(row).assertTouchTargetIsAtLeast()
        }
    }

    @Test
    fun `every row keeps 48 dp at the largest font size`() {
        show(scale = 2f)
        openMenu()

        for (row in ROWS) {
            compose.onNodeWithText(row).assertTouchTargetIsAtLeast()
        }
    }

    @Test
    fun `a long press on the cover opens the same menu`() {
        show()

        compose.onNode(SemanticsMatcher.keyIsDefined(SemanticsActions.OnLongClick)).performTouchInput { longClick() }

        for (row in ROWS) compose.onNodeWithText(row).assertExists()
    }

    @Test
    fun `removing asks first and only the confirmation removes`() {
        val removed = AtomicInteger()
        show(CoverMenu(onChoose = {}, onRemove = { removed.incrementAndGet() }))
        openMenu()

        compose.onNodeWithText(REMOVE).performClick()
        assertEquals("the row removed the cover before asking", 0, removed.get())
        compose.onNodeWithText("Remove this cover?").assertExists()
        compose.onNodeWithText("Cancel").performClick()
        assertEquals("dismissing removed the cover", 0, removed.get())

        openMenu()
        compose.onNodeWithText(REMOVE).performClick()
        compose.onNodeWithText(REMOVE).performClick()
        assertEquals(1, removed.get())
    }

    @Test
    fun `a hero with a cover choice carries the edit button at 48 dp`() {
        compose.setContent {
            StoryArcTheme {
                DetailHero(
                    publication = app.storyarc.core.model.Publication(
                        identity = app.storyarc.core.model.PublicationIdentity(contentDigest = "t"),
                        format = app.storyarc.core.model.PublicationFormat.CBZ,
                        displayTitle = "Fine Print",
                        origin = app.storyarc.core.model.MetadataOrigin.INFERRED,
                    ),
                    cover = null,
                    accent = null,
                    layout = DetailHeroLayout(isSideBySide = false, coverHeight = 360.dp),
                    coverChoice = CoverChoice(onChoose = {}),
                ) {}
            }
        }
        compose.waitForIdle()

        compose.onNodeWithContentDescription(EDIT)
            .assertTouchTargetIsAtLeast()
        compose.onNodeWithText("Add a cover").assertTouchTargetIsAtLeast()
    }

    private companion object {
        const val EDIT = "Edit cover"
        const val REMOVE = "Remove cover"
        val ROWS = listOf(
            "Choose a picture",
            "Find a cover",
            "Find a cover on the web",
            "Send this cover to the server",
            REMOVE,
        )
    }
}
