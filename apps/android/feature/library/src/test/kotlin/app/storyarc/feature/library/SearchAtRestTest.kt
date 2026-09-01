package app.storyarc.feature.library

import androidx.compose.ui.res.stringResource
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The search page draws the sections it has and no others.
 *
 * `navigation-shell`'s *Nothing to suggest* is a rendering rule, not an arithmetic one:
 * "the screen says so in one sentence **rather than drawing empty headings**". No pure test
 * can tell those two apart — [SearchSuggestionsTest] can say a list is empty, and only a
 * composition can say whether a heading was drawn over it.
 *
 * `GraphicsMode.NATIVE` and a real window size for the same reason `ListOrderChipsWrapTest`
 * gives: legacy graphics measure every string as roughly a pixel per glyph, and a lazy list
 * in an unmeasured window composes nothing at all.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
// Robolectric ships an image per API level and has none for 37, so it cannot be handed the
// module's target. 34 is inside its range and above the minimum this app supports, and none
// of the questions here has an API level in it.
@Config(sdk = [34], qualifiers = "w400dp-h1600dp")
class SearchAtRestTest {

    @get:Rule
    val compose = createComposeRule()

    @Test
    fun `a section with nothing in it draws no heading`() {
        val labels = show(
            SearchSuggestions(neverOpened = listOf(entry("Tin Kingdom"))),
        )

        compose.onNodeWithText(labels.neverOpened).assertIsDisplayed()
        // The other two are absent rather than present and empty. A heading over no covers
        // tells a reader they have something to continue when they have not.
        compose.onNodeWithText(labels.inProgress).assertDoesNotExist()
        compose.onNodeWithText(labels.nextInSeries).assertDoesNotExist()
    }

    @Test
    fun `all three headings are drawn when all three have something`() {
        val labels = show(
            SearchSuggestions(
                inProgress = listOf(entry("Harbour Lights")),
                nextInSeries = listOf(entry("Cinder Season")),
                neverOpened = listOf(entry("Tin Kingdom")),
            ),
        )

        compose.onNodeWithText(labels.inProgress).assertIsDisplayed()
        compose.onNodeWithText(labels.nextInSeries).assertIsDisplayed()
        compose.onNodeWithText(labels.neverOpened).assertIsDisplayed()
    }

    @Test
    fun `nothing to suggest is one sentence and no empty headings`() {
        val labels = show(SearchSuggestions())

        compose.onNodeWithText(labels.emptyTitle).assertIsDisplayed()
        compose.onNodeWithText(labels.openComic).assertIsDisplayed()
        compose.onNodeWithText(labels.inProgress).assertDoesNotExist()
        compose.onNodeWithText(labels.nextInSeries).assertDoesNotExist()
        compose.onNodeWithText(labels.neverOpened).assertDoesNotExist()
    }

    @Test
    fun `nothing to suggest offers all five of the library's own ways in`() {
        // `navigation-shell`'s *Nothing to suggest*: the screen "offers the same way of adding
        // a source that the library's own empty state offers" — and `EmptyLibrary` offers
        // five. Two of them were wired here and the other three were absent, so a reader who
        // reached this page could add a folder and a file and had no way at all to reach a
        // catalogue, a Kavita server or a share. All five are read out of the same resources
        // `EmptyLibrary`'s own menu draws, so one of the two losing a row fails this.
        val labels = show(SearchSuggestions())

        compose.onNodeWithText(labels.addSource).performClick()

        compose.onNodeWithText(labels.addFolder).assertIsDisplayed()
        compose.onNodeWithText(labels.importFile).assertIsDisplayed()
        compose.onNodeWithText(labels.catalogue).assertIsDisplayed()
        compose.onNodeWithText(labels.kavita).assertIsDisplayed()
        compose.onNodeWithText(labels.share).assertIsDisplayed()
    }

    @Test
    fun `each of the five ways in reaches its own action`() {
        // Wired, not merely drawn. The three that open a sheet the app layer owns were the
        // ones missing, and a menu item that does nothing is worse than one that is not there.
        val reached = mutableListOf<String>()
        val labels = show(
            SearchSuggestions(),
            onOpenComic = { reached += "comic" },
            onAddFolder = { reached += "folder" },
            onAddCatalogue = { reached += "catalogue" },
            onAddKavita = { reached += "kavita" },
            onAddShare = { reached += "share" },
        )

        for (label in listOf(labels.addFolder, labels.importFile, labels.catalogue, labels.kavita, labels.share)) {
            compose.onNodeWithText(labels.addSource).performClick()
            compose.onNodeWithText(label).performClick()
        }

        assertEquals(listOf("folder", "comic", "catalogue", "kavita", "share"), reached)
    }

    @Test
    fun `the scope is stated before a letter is typed`() {
        // `library-browsing` asks the screen to state its scope "when the search screen is
        // open". The chips inside the expanded bar cannot satisfy that on their own: a reader
        // who has not pressed to type has never seen them.
        val labels = show(SearchSuggestions(neverOpened = listOf(entry("Tin Kingdom"))))

        compose.onNodeWithText(labels.everywhere).assertIsDisplayed()
        compose.onNodeWithText(labels.onThisDevice).assertIsDisplayed()
    }

    @Test
    fun `the scope is stated on the page with nothing to suggest as well`() {
        // A reader who has narrowed to what is on the device and finds nothing to suggest
        // needs to be able to see the narrowing, or the empty page is telling them something
        // untrue about their library.
        val labels = show(SearchSuggestions())

        compose.onNodeWithText(labels.everywhere).assertIsDisplayed()
        compose.onNodeWithText(labels.onThisDevice).assertIsDisplayed()
    }

    @Test
    fun `a suggestion leads to the publication's own page`() {
        // Two verbs, and `publication-detail` makes them two: every cover in the grid, the
        // list and the search results reaches the page. Only Home's Keep reading card resumes.
        var opened: String? = null
        show(
            SearchSuggestions(neverOpened = listOf(entry("Tin Kingdom"))),
            onOpenPage = { opened = it.displayTitle },
        )

        // By the card's own description, not by its title: `homeCardSemantics` merges the
        // cover, the title and how much is left into one target, so the title alone matches
        // two nodes in the unmerged tree and none in the merged one.
        compose.onNodeWithContentDescription("Tin Kingdom", substring = true).performClick()

        assertEquals("Tin Kingdom", opened)
    }

    @Test
    fun `a book the reader has never opened is not announced as part-read`() {
        // `homeRemainingText`'s fallback for a publication that declares no page count is
        // "part-read", which is true of every shelf Home draws it for and false of two of the
        // three sections here. Found on a device: every card under *You have never opened
        // these* announced itself as part-read.
        show(SearchSuggestions(neverOpened = listOf(entry("Tin Kingdom"))))

        compose.onNodeWithContentDescription("Tin Kingdom").assertExists()
    }

    @Test
    fun `a book part-way through still says how much is left`() {
        show(
            SearchSuggestions(
                inProgress = listOf(entry("Harbour Lights", fraction = 0.4, pagesRemaining = 12)),
            ),
        )

        compose.onNodeWithContentDescription("Harbour Lights", substring = true)
            .assertExists()
        compose.onNodeWithContentDescription("Harbour Lights").assertDoesNotExist()
    }

    // Fixtures

    /** Every label this screen can draw, read out of the resources it actually uses. */
    private class Labels(
        val inProgress: String,
        val nextInSeries: String,
        val neverOpened: String,
        val emptyTitle: String,
        val openComic: String,
        val addSource: String,
        val addFolder: String,
        val importFile: String,
        val catalogue: String,
        val kavita: String,
        val share: String,
        val everywhere: String,
        val onThisDevice: String,
    )

    private fun show(
        suggestions: SearchSuggestions,
        onOpenPage: (Publication) -> Unit = {},
        onOpenComic: () -> Unit = {},
        onAddFolder: () -> Unit = {},
        onAddCatalogue: () -> Unit = {},
        onAddKavita: () -> Unit = {},
        onAddShare: () -> Unit = {},
    ): Labels {
        lateinit var labels: Labels
        compose.setContent {
            labels = Labels(
                inProgress = stringResource(R.string.search_suggestions_in_progress),
                nextInSeries = stringResource(R.string.search_suggestions_next_in_series),
                neverOpened = stringResource(R.string.search_suggestions_never_opened),
                emptyTitle = stringResource(R.string.search_empty_title),
                openComic = stringResource(R.string.library_open_comic),
                addSource = stringResource(R.string.library_add_source),
                addFolder = stringResource(R.string.library_add_folder),
                importFile = stringResource(R.string.library_import),
                catalogue = stringResource(R.string.catalogue_title),
                kavita = stringResource(R.string.kavita_title),
                share = stringResource(R.string.smb_title),
                everywhere = stringResource(R.string.library_scope_all),
                onThisDevice = stringResource(R.string.source_on_this_device),
            )
            StoryArcTheme {
                SearchAtRest(
                    suggestions = suggestions,
                    scope = LibraryAvailability.EVERYTHING,
                    onScopeChange = {},
                    // No cover art in a unit test, and none is needed: what is asserted here
                    // is which headings exist, which is decided before a bitmap arrives.
                    cover = { _, _ -> null },
                    onOpenPage = onOpenPage,
                    onOpenComic = onOpenComic,
                    onAddFolder = onAddFolder,
                    onAddCatalogue = onAddCatalogue,
                    onAddKavita = onAddKavita,
                    onAddShare = onAddShare,
                )
            }
        }
        compose.waitForIdle()
        return labels
    }

    private fun entry(
        title: String,
        fraction: Double = 0.0,
        pagesRemaining: Int? = null,
    ) = HomeEntry(
        publication = Publication(
            identity = PublicationIdentity(normalizedPath = "/library/$title.cbz"),
            format = PublicationFormat.CBZ,
            displayTitle = title,
            origin = MetadataOrigin.EMBEDDED,
        ),
        isReadableNow = true,
        pagesRemaining = pagesRemaining,
        fraction = fraction,
    )
}
