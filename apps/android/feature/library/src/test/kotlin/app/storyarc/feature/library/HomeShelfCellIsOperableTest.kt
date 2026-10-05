package app.storyarc.feature.library

import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performSemanticsAction
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadState
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * A cover on a plain home shelf can be opened and held by a reader who cannot touch it.
 *
 * [HomeCellSaysWhatIsTrueTest] asks what the cell *says*; this asks what it can *do*. The two
 * are separate questions and the cell answered only the first: `homeCardSemantics` is
 * `clearAndSetSemantics`, and the cell applied the caller's modifier before its own
 * `combinedClickable`. Compose collapses a modifier chain from the inside out and starts the
 * configuration again at a clearing node, so the tap and the long press were applied first and
 * then thrown away. A sighted reader kept both; TalkBack was handed a label and no way to act
 * on it, which is the one surface `library-browsing`'s *A publication's actions wherever it is
 * drawn* was fixed for.
 *
 * Touch injection cannot see this defect: a gesture reaches the pointer-input node whether or
 * not the semantics tree reports an action. Only the semantics action can, so both cases drive
 * the cell the way an accessibility service does.
 *
 * `GraphicsMode.NATIVE` for the reason `ListOrderChipsWrapTest` gives.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w411dp-h891dp")
class HomeShelfCellIsOperableTest {

    @get:Rule
    val compose = createComposeRule()

    private val entry = HomeEntry(
        publication = Publication(
            identity = PublicationIdentity(contentDigest = "salt-and-iron"),
            format = PublicationFormat.CBZ,
            displayTitle = "Salt and Iron",
            origin = MetadataOrigin.INFERRED,
        ),
        isReadableNow = true,
        pagesRemaining = null,
        fraction = 0.0,
        state = ReadState.UNREAD,
    )

    private val opened = mutableListOf<String>()
    private val held = mutableListOf<String>()

    private fun show() {
        compose.setContent {
            StoryArcTheme {
                HomeScreen(
                    surface = HomeSurface(recentlyAdded = listOf(entry)),
                    cover = { _, _ -> null },
                    onOpen = { opened += it.displayTitle },
                    onResume = {},
                    onFinish = {},
                    onShowAll = {},
                    onOpenFile = {},
                    onAddFolder = {},
                    onAddCatalogue = {},
                    onAddKavita = {},
                    onAddShare = {},
                    actions = HomePublicationActions(
                        onMark = { publication, _ -> held += publication.displayTitle },
                        onRestart = {},
                        onAddToShelf = {},
                        onDownload = {},
                        onRemoveDownload = {},
                    ),
                )
            }
        }
        compose.waitForIdle()
    }

    @Test
    fun `a screen reader can open a cover on a plain shelf`() {
        show()

        compose.onNodeWithContentDescription("Salt and Iron")
            .performSemanticsAction(SemanticsActions.OnClick)

        assertEquals(listOf("Salt and Iron"), opened)
    }

    @Test
    fun `a screen reader can hold a cover on a plain shelf to reach its actions`() {
        show()

        compose.onNodeWithContentDescription("Salt and Iron")
            .performSemanticsAction(SemanticsActions.OnLongClick)

        compose.onNodeWithText("Mark as read").assertExists()
    }
}
