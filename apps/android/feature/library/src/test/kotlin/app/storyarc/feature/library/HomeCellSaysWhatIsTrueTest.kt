package app.storyarc.feature.library

import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadState
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * What a cover on a plain home shelf announces to a screen reader.
 *
 * Measured on an emulator with the app's data freshly cleared — nothing opened, no reading
 * record of any kind — every cell on *Recently added* read "Salt and Iron. Part-read",
 * "Bright Panels. Part-read", "Broken Transfer. Part-read". "Part-read" was the caption's
 * fallback for *this publication does not say how many pages it has*, and a book nobody has
 * opened does not say either.
 *
 * That is also what a design review read as evidence that the surface knew about reading it
 * was not showing. It did not: `Keep reading` appears the moment anything is genuinely in
 * progress, which the same emulator confirms one page-turn later.
 *
 * `GraphicsMode.NATIVE` for the reason `ListOrderChipsWrapTest` gives.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w411dp-h891dp")
class HomeCellSaysWhatIsTrueTest {

    @get:Rule
    val compose = createComposeRule()

    private fun entry(title: String, state: ReadState, pagesRemaining: Int? = null) = HomeEntry(
        publication = Publication(
            identity = PublicationIdentity(contentDigest = title),
            format = PublicationFormat.CBZ,
            displayTitle = title,
            origin = MetadataOrigin.INFERRED,
        ),
        isReadableNow = true,
        pagesRemaining = pagesRemaining,
        fraction = if (state == ReadState.FINISHED) 1.0 else 0.0,
        state = state,
    )

    private fun show(vararg entries: HomeEntry) {
        compose.setContent {
            StoryArcTheme {
                HomeScreen(
                    surface = HomeSurface(recentlyAdded = entries.toList()),
                    cover = { _, _ -> null },
                    onOpen = {},
                    onResume = {},
                    onShowAll = {},
                    onOpenFile = {},
                    onAddFolder = {},
                )
            }
        }
    }

    @Test
    fun aBookNobodyHasOpenedAnnouncesItsTitleAndNothingElse() {
        show(entry("Salt and Iron", ReadState.UNREAD))

        compose.onNodeWithContentDescription("Salt and Iron").assertExists()
    }

    @Test
    fun aFinishedBookIsNotAnnouncedAsPartRead() {
        // `HomeShelves.pagesRemaining` is deliberately null once the finished flag is set,
        // so the old caption called a finished book part-read as well.
        show(entry("Glasshouse", ReadState.FINISHED))

        compose.onNodeWithContentDescription("Glasshouse. Finished").assertExists()
    }

    @Test
    fun aPartReadBookStillSaysHowMuchIsLeft() {
        show(entry("Tidal Reach 01", ReadState.IN_PROGRESS, pagesRemaining = 2))

        compose.onNodeWithContentDescription("Tidal Reach 01. 2 pages left").assertExists()
    }

    @Test
    fun aPartReadBookWithNoPageCountFallsBackToTheSentence() {
        show(entry("Bright Panels", ReadState.IN_PROGRESS))

        compose.onNodeWithContentDescription("Bright Panels. Part-read").assertExists()
    }
}
