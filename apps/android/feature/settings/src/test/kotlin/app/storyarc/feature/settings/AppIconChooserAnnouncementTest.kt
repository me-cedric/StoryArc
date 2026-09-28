package app.storyarc.feature.settings

import android.content.ComponentName
import android.content.Context
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.AppIconChoice
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Each icon option is announced by name and by whether it is in use, and the tile is silent.
 *
 * `settings-and-about`, *Announced without sight*: an option "is announced by name and by
 * whether it is the one in use, and never as an unlabelled image", and "the tile itself is
 * decorative to assistive technology, because the name is what identifies it".
 *
 * The tile clause is the one nothing held. `AppIconGroup` passes `contentDescription = null`
 * to the tile's `Image`, and a hand that gave it a description would make every row announce
 * "image, Paper" — a compiling, screenshot-identical change no gate could see. iOS has this
 * case too, at `AppIconChooserAnnouncementTests.swift:183`, and it fails there.
 *
 * The chooser is composed rather than read, so what is asked is what the tree says rather
 * than what the source spells. `AppIconRefusalNamesNoFaceTest` owns the refusal sentences.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
// Robolectric ships no image for API 37, and nothing here has an API level in it.
@Config(sdk = [34], qualifiers = "w320dp-h640dp")
class AppIconChooserAnnouncementTest {

    @get:Rule
    val compose = createComposeRule()

    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private fun name(face: AppIconChoice): String = context.getString(face.labelRes)

    /**
     * A device with the five aliases installed, so every row has a tile to draw.
     *
     * Without it the tile is the claim's blind spot rather than its subject: the tile is the
     * component's own launcher drawable, asked of `PackageManager`, and off a device nothing
     * is installed — so [AppIconGroup] draws no `Image` and a description added to it would be
     * invisible here. A registered component answers with the default application icon, which
     * is a real drawable and all this suite needs. `AppIconChooserLayoutTest` does the same.
     */
    @Before
    fun installTheAliases() {
        val packages = Shadows.shadowOf(context.packageManager)
        AppIconChoice.entries.forEach { face ->
            packages.addActivityIfNotPresent(
                ComponentName(context.packageName, face.componentClassName),
            )
        }
    }

    private fun showChooser() {
        compose.setContent { StoryArcTheme { AppIconGroup() } }
    }

    /** Every node under the root, unmerged, so a tile's own node is visible beside its row's. */
    private fun everyNode(): List<SemanticsNode> {
        fun walk(node: SemanticsNode): List<SemanticsNode> =
            listOf(node) + node.children.flatMap(::walk)
        return walk(compose.onRoot(useUnmergedTree = true).fetchSemanticsNode())
    }

    @Test
    fun `every face is one element that says its name and whether it is in use`() {
        showChooser()

        AppIconChoice.entries.forEach { face ->
            val row = compose.onNodeWithText(name(face)).fetchSemanticsNode()
            assertTrue(
                "${face.name}'s row carries no selected state, so a reader without sight is" +
                    " never told which face is theirs.",
                row.config.getOrNull(SemanticsProperties.Selected) != null,
            )
        }
    }

    @Test
    fun `nothing the chooser draws is announced by a description`() {
        showChooser()

        val described = everyNode()
            .mapNotNull { it.config.getOrNull(SemanticsProperties.ContentDescription) }
            .flatten()

        assertEquals(
            "The chooser describes $described to assistive technology. A face is identified by" +
                " its name, so a second description on any part of the row makes it read" +
                " twice — once as a thing, once as the face.",
            emptyList<String>(),
            described,
        )
    }

    @Test
    fun `one face is announced as in use, and it is the one the platform draws`() {
        showChooser()

        val inUse = AppIconChoice.entries.filter { face ->
            compose.onNodeWithText(name(face)).fetchSemanticsNode()
                .config.getOrNull(SemanticsProperties.Selected) == true
        }
        assertEquals(
            "The chooser marks $inUse as in use. A reader without sight is told which face is" +
                " theirs by this state alone, so two marks and no mark are the same failure.",
            listOf(AppIconChoice.entries.first { it.isDefault }),
            inUse,
        )
    }
}
