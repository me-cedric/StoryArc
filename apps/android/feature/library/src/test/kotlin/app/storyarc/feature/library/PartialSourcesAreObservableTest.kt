package app.storyarc.feature.library

import android.app.Application
import androidx.compose.material3.Text
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.test.core.app.ApplicationProvider
import java.util.UUID
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Task 22.1's own correction: "Android source detail does not update while it is open" --
 * [LibraryViewModel.partialSources] was a plain `var`, so a page arriving in the background
 * while a source's row was on screen changed what [LibraryViewModel.isPartial] and
 * [readProgress] would answer next time, and told Compose nothing about it. A screen that had
 * already composed kept showing the count it opened with until something else gave it a
 * reason to recompose.
 *
 * This draws a composable exactly the way `SourcesGroup` and `SettingsHost` do -- a `Text`
 * built from `viewModel.isPartial(id)` and `viewModel.readProgress(id)`, read during
 * composition rather than hoisted into a `remember` -- and mutates the view model from
 * outside the composition, the way `KavitaContinuedRead`'s background loop does. No manual
 * recompose is triggered; `mutableStateOf` is what has to do that on its own.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class PartialSourcesAreObservableTest {

    @get:Rule
    val compose = createComposeRule()

    @Test
    fun `a source's row recomposes when the background read advances it`() {
        val library = LibraryViewModel(ApplicationProvider.getApplicationContext<Application>())
        val sourceId = UUID.randomUUID()

        compose.setContent {
            val partial = library.isPartial(sourceId)
            val read = library.readProgress(sourceId)?.read
            Text(if (partial) "partial: $read" else "complete")
        }

        compose.onNodeWithText("complete").assertExists()

        library.partialSources = mapOf(sourceId to SourceReadProgress.started(firstSliceRead = 60))
        compose.waitForIdle()

        compose.onNodeWithText("partial: 60").assertExists()

        library.partialSources = mapOf(
            sourceId to SourceReadProgress.started(firstSliceRead = 60).copy(read = 120),
        )
        compose.waitForIdle()

        compose.onNodeWithText("partial: 120").assertExists()
    }
}
