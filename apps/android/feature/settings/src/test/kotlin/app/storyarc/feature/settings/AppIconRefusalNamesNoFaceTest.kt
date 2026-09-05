package app.storyarc.feature.settings

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotSelected
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performSemanticsAction
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.AppIconChoice
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * A refusal on a launcher that draws no face names none — and one that draws a face names it.
 *
 * `settings-and-about`, *The platform refuses*: the app "names which one is still in use where
 * one is", and "where no icon is in use at all — reachable on Android, where the aliases can
 * all be disabled from outside the app — it says the change was refused without naming a
 * face, because there is none to name". `AppIconSwitcherTest` proves `applied()` answers
 * `null` on that device; `AppIconGroup` picks `app_icon_refused_none` when it does; and
 * `brand-identity-and-app-icons` was archived with nothing asserting that the composable
 * picks it.
 *
 * **The real group is composed over a refusing device.** `SettingsSemanticsTest` composes the
 * real screen too, but it is instrumented — compiled by `pnpm build:android:tests` and run by
 * nothing in the gate — and a device it runs on cannot be made to refuse. Robolectric can:
 * [RefusingPackageManager] takes the framework shadow's place and throws on the write, and the
 * aliases are disabled through the ordinary `PackageManager` first. What is then asked of the
 * tree is which sentence sits under the title, and whether any row claims to be in use.
 *
 * Three cases rather than one, because the sentence has three answers and a test of the new
 * one alone would pass against a group that always said it.
 */
@RunWith(RobolectricTestRunner::class)
// Robolectric ships an image per API level and has none for 37, so it cannot be handed the
// module's target. 34 is inside its range and above the minimum this app supports.
@Config(sdk = [34], shadows = [RefusingPackageManager::class])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class AppIconRefusalNamesNoFaceTest {

    @get:Rule
    val compose = createComposeRule()

    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private fun string(id: Int, vararg arguments: Any): String = context.getString(id, *arguments)
    private fun name(face: AppIconChoice): String = string(face.labelRes)

    /** A fresh device: every alias as the manifest declares it, and a platform that accepts. */
    @Before
    fun freshDevice() {
        RefusingPackageManager.refuses = false
        setEveryAlias(PackageManager.COMPONENT_ENABLED_STATE_DEFAULT)
    }

    @After
    fun accept() {
        RefusingPackageManager.refuses = false
    }

    private fun setEveryAlias(state: Int) {
        val packages = context.packageManager
        AppIconChoice.entries.forEach { face ->
            packages.setComponentEnabledSetting(
                ComponentName(context.packageName, face.componentClassName),
                state,
                PackageManager.DONT_KILL_APP,
            )
        }
    }

    private fun showChooser() {
        compose.setContent { StoryArcTheme { AppIconGroup() } }
    }

    /**
     * The semantics action rather than `performClick`, for the reason `SkippedNoticeTest`
     * gives: a synthesised touch does not reliably reach a `selectable` under Robolectric's own
     * view host, and the question is whether the row is wired to the reader's intent.
     */
    private fun press(face: AppIconChoice) {
        compose.onNodeWithText(name(face))
            .assertHasClickAction()
            .performSemanticsAction(SemanticsActions.OnClick)
        compose.waitForIdle()
    }

    @Test
    fun `a launcher drawing no face refuses without naming one`() {
        // The device `AppIconSwitcherTest` describes: every alias off, from outside the app.
        setEveryAlias(PackageManager.COMPONENT_ENABLED_STATE_DISABLED)
        RefusingPackageManager.refuses = true
        showChooser()

        // "no face is shown as in use": nothing is drawn, so no row claims to be.
        AppIconChoice.entries.forEach { compose.onNodeWithText(name(it)).assertIsNotSelected() }
        compose.onNodeWithText(string(R.string.app_icon_note)).assertIsDisplayed()

        press(AppIconChoice.PAPER)

        // Refused, and no face named — there is none to name.
        compose.onNodeWithText(string(R.string.app_icon_refused_none)).assertIsDisplayed()
        AppIconChoice.entries.forEach { face ->
            compose.onNodeWithText(string(R.string.app_icon_refused, name(face))).assertDoesNotExist()
        }
        compose.onNodeWithText(string(R.string.app_icon_note)).assertDoesNotExist()
        AppIconChoice.entries.forEach { compose.onNodeWithText(name(it)).assertIsNotSelected() }
    }

    @Test
    fun `a refusal with a face still in use names that face`() {
        RefusingPackageManager.refuses = true
        showChooser()
        compose.onNodeWithText(name(AppIconChoice.INK)).assertIsSelected()

        press(AppIconChoice.PAPER)

        // The other sentence, and only it: the face still drawn is the one named.
        compose.onNodeWithText(string(R.string.app_icon_refused, name(AppIconChoice.INK))).assertIsDisplayed()
        compose.onNodeWithText(string(R.string.app_icon_refused_none)).assertDoesNotExist()
        compose.onNodeWithText(name(AppIconChoice.INK)).assertIsSelected()
        compose.onNodeWithText(name(AppIconChoice.PAPER)).assertIsNotSelected()
    }

    @Test
    fun `a change the platform accepts marks the new face and keeps the note`() {
        showChooser()
        compose.onNodeWithText(name(AppIconChoice.INK)).assertIsSelected()

        press(AppIconChoice.PAPER)

        // The control for the two refusals: the same press over a platform that says yes moves
        // the mark and leaves the note where it was.
        compose.onNodeWithText(name(AppIconChoice.PAPER)).assertIsSelected()
        compose.onNodeWithText(name(AppIconChoice.INK)).assertIsNotSelected()
        compose.onNodeWithText(string(R.string.app_icon_note)).assertIsDisplayed()
        compose.onNodeWithText(string(R.string.app_icon_refused_none)).assertDoesNotExist()
    }
}
