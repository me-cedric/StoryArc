package app.storyarc.feature.library

import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.test.core.app.ApplicationProvider
import android.content.Context
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceKind
import app.storyarc.core.model.SourceRegistry
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The strip draws the line the decision picked, and only that one.
 *
 * [SourceRefreshTest] asserts the ranking without a screen. This asserts the other half:
 * that each branch reaches a composable and that the reader sees one line, not two. A
 * decision nothing draws and a drawing nothing decides are the two ways this can be wrong.
 *
 * The refreshing line is the one that did not exist. `sources`' *A refresh nobody asked
 * for* is the requirement, and before it the shelf drew nothing on four of the five
 * occasions a refresh starts.
 *
 * `GraphicsMode.NATIVE` and `sdk = [34]` for the reasons [KavitaCardFactsTest] gives.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34])
class LibraryNoticesTest {

    @get:Rule
    val compose = createComposeRule()

    private val context: Context = ApplicationProvider.getApplicationContext()

    private fun server(
        state: SourceConnectionState = SourceConnectionState.Connected,
        answeredAt: Long? = null,
    ) = Source(
        displayName = "Kavita",
        kind = SourceKind.KAVITA_SERVER,
        state = state,
        lastSuccessfulSyncEpochMillis = answeredAt,
        locator = "https://x.invalid",
    )

    private fun show(
        cachedAt: Long? = null,
        refreshing: SourceRefreshOrigin? = null,
        registry: SourceRegistry = SourceRegistry(),
    ) {
        compose.setContent {
            StoryArcTheme { LibraryNotices(cachedAt, refreshing, registry, emptyList()) }
        }
    }

    private fun word(id: Int) = context.getString(id).substringBefore(" %").trim()

    @Test
    fun `a refresh nobody asked for is stated on the shelf`() {
        show(refreshing = SourceRefreshOrigin.AUTOMATIC)

        compose.onNodeWithText(context.getString(R.string.library_refreshing)).assertIsDisplayed()
    }

    @Test
    fun `a pulled refresh puts no line on the shelf, because the pull indicator is up`() {
        show(refreshing = SourceRefreshOrigin.PULLED)

        compose.onAllNodesWithText(context.getString(R.string.library_refreshing))
            .assertCountEquals(0)
    }

    @Test
    fun `when nothing is running the shelf says when the sources last answered`() {
        show(registry = SourceRegistry().adding(server(answeredAt = 1_000L)))

        compose.onAllNodesWithText(word(R.string.library_checked), substring = true)
            .assertCountEquals(1)
    }

    @Test
    fun `a library whose sources have never answered draws no line at all`() {
        show(registry = SourceRegistry().adding(server()))

        compose.onAllNodesWithText(word(R.string.library_checked), substring = true)
            .assertCountEquals(0)
        compose.onAllNodesWithText(context.getString(R.string.library_refreshing))
            .assertCountEquals(0)
    }

    @Test
    fun `a cached shelf keeps its own line while a refresh runs, rather than showing both`() {
        // `library_cached` already ends "Checking for changes", so a refreshing line above
        // it would say the second half twice.
        show(
            cachedAt = 1_000L,
            refreshing = SourceRefreshOrigin.AUTOMATIC,
            registry = SourceRegistry().adding(server(answeredAt = 1_000L)),
        )

        compose.onAllNodesWithText(word(R.string.library_cached), substring = true)
            .assertCountEquals(1)
        compose.onAllNodesWithText(context.getString(R.string.library_refreshing))
            .assertCountEquals(0)
    }
}
