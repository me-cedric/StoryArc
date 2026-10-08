package app.storyarc.feature.settings

import android.content.Context
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.SourceDiagnosis
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * `library-portability` tasks 2.5 and 3.1: Sources offers the two rows that move a library, and
 * only where there are stores behind them. iOS's `LibraryTransferRowsTests` asserts the same rows.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w360dp-h800dp")
class SourcesGroupTransferRowsTest {

    @get:Rule
    val compose = createComposeRule()

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    private fun isDrawn(text: String) =
        compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty()

    private fun show(withTransfer: Boolean) {
        val transfer = if (withTransfer) TransferDevice(context).transfer else null
        compose.setContent {
            StoryArcTheme {
                SourcesGroup(
                    sources = emptyList(),
                    itemCount = { 0 },
                    diagnose = { source -> SourceDiagnosis.of(source, itemCount = 0, downloads = emptyList()) },
                    onRemove = {},
                    onRename = { _, _ -> },
                    transfer = transfer,
                )
            }
        }
        compose.waitForIdle()
    }

    @Test
    fun `with stores behind it the group draws the two rows and what they move`() {
        show(withTransfer = true)

        assertTrue(isDrawn(context.getString(R.string.transfer_export)))
        assertTrue(isDrawn(context.getString(R.string.transfer_import)))
        assertTrue(isDrawn(context.getString(R.string.transfer_section_footer)))
    }

    @Test
    fun `with none the two rows are not drawn`() {
        show(withTransfer = false)

        assertFalse(isDrawn(context.getString(R.string.transfer_export)))
        assertFalse(isDrawn(context.getString(R.string.transfer_import)))
    }
}
