package app.storyarc.feature.settings

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceDiagnosis
import app.storyarc.core.model.SourceKind
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The source detail screen states how a share is reached, and whether that is encrypted.
 *
 * `network-share`'s *Encrypted transport*: "the source detail screen states whether the
 * connection is encrypted".
 *
 * **The screen used to draw one fixed string.** It said the connection is not encrypted
 * whatever the code had measured, so it made a claim about a reader's security that nothing
 * had checked. The tests that mattered are the first two below: they draw the screen with
 * each measurement and read back which sentence appeared. Against the old screen the first
 * one fails, because the old screen drew the same sentence for both answers.
 *
 * **Neither client encrypts today**, so a reader only ever sees the plain sentence. The
 * encrypted answer is still drawn here, because the point of the change is that the screen
 * follows the value instead of repeating an answer.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], qualifiers = "w400dp-h1600dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class SourceTransportNoteTest {

    @get:Rule
    val compose = createComposeRule()

    /** The two sentences, as this composition resolves them. */
    private data class Sentences(val plain: String, val encrypted: String)

    /**
     * Draws the screen once and reports both sentences.
     *
     * Once, because `setContent` may be called only once for each test. A test that needs
     * the other measurement asks for another screen in a test of its own.
     */
    private fun show(
        kind: SourceKind,
        state: SourceConnectionState = SourceConnectionState.Connected,
        isEncrypted: Boolean = false,
        fontScale: Float = 1f,
    ): Sentences {
        var sentences = Sentences("", "")
        compose.setContent {
            sentences = Sentences(
                plain = stringResource(R.string.sources_detail_transport_plain),
                encrypted = stringResource(R.string.sources_detail_transport_encrypted),
            )
            CompositionLocalProvider(
                LocalDensity provides Density(density = 1f, fontScale = fontScale),
            ) {
                StoryArcTheme {
                    val source = Source(displayName = "Fixture", kind = kind, state = state)
                    SourceDetailScreen(
                        source = source,
                        diagnosis = SourceDiagnosis.of(
                            source,
                            itemCount = 3,
                            downloads = emptyList(),
                        ),
                        onAction = {},
                        onBack = {},
                        isTransportEncrypted = isEncrypted,
                    )
                }
            }
        }
        compose.waitForIdle()
        return sentences
    }

    @Test
    fun `a share whose connection is encrypted states that it is encrypted`() {
        val sentences = show(SourceKind.NETWORK_SHARE, isEncrypted = true)
        compose.onNodeWithText(sentences.encrypted).assertIsDisplayed()
        compose.onNodeWithText(sentences.plain).assertDoesNotExist()
    }

    @Test
    fun `a share whose connection is not encrypted says so`() {
        val sentences = show(SourceKind.NETWORK_SHARE, isEncrypted = false)
        compose.onNodeWithText(sentences.plain).assertIsDisplayed()
        compose.onNodeWithText(sentences.encrypted).assertDoesNotExist()
    }

    @Test
    fun `the rule answers a different sentence for each measurement`() {
        assertNotEquals(
            transportNote(SourceKind.NETWORK_SHARE, isEncrypted = true),
            transportNote(SourceKind.NETWORK_SHARE, isEncrypted = false),
        )
    }

    @Test
    fun `no other kind of source has a transport to state`() {
        for (kind in SourceKind.entries.filter { it != SourceKind.NETWORK_SHARE }) {
            assertNull("$kind", transportNote(kind, isEncrypted = false))
            assertNull("$kind", transportNote(kind, isEncrypted = true))
        }
    }

    @Test
    fun `a folder states neither sentence, because a folder is a disk`() =
        assertNeitherSentenceIsDrawn(SourceKind.LOCAL_FOLDER)

    @Test
    fun `an OPDS catalogue states neither, because it is reached over HTTP`() =
        assertNeitherSentenceIsDrawn(SourceKind.OPDS_CATALOG)

    @Test
    fun `kavita states neither, for the same reason`() =
        assertNeitherSentenceIsDrawn(SourceKind.KAVITA_SERVER)

    private fun assertNeitherSentenceIsDrawn(kind: SourceKind) {
        val sentences = show(kind)
        compose.onNodeWithText(sentences.plain).assertDoesNotExist()
        compose.onNodeWithText(sentences.encrypted).assertDoesNotExist()
    }

    @Test
    fun `a refused credential leaves the sentence alone`() {
        val sentences = show(
            SourceKind.NETWORK_SHARE,
            SourceConnectionState.Unauthorized("The password was refused."),
        )
        compose.onNodeWithText(sentences.plain).assertIsDisplayed()
    }

    @Test
    fun `an unreachable share leaves the sentence alone`() {
        val sentences = show(SourceKind.NETWORK_SHARE, SourceConnectionState.Unreachable(0L))
        compose.onNodeWithText(sentences.plain).assertIsDisplayed()
    }

    @Test
    fun `the English pair reads correctly and claims nothing about signing`() =
        assertThePairReadsCorrectly("not encrypted")

    @Test
    @Config(qualifiers = "fr-rFR-w400dp-h1600dp")
    fun `the French pair reads correctly and claims nothing about signing`() =
        assertThePairReadsCorrectly("pas chiffr")

    @Test
    @Config(qualifiers = "de-rDE-w400dp-h1600dp")
    fun `the German pair reads correctly and claims nothing about signing`() =
        assertThePairReadsCorrectly("nicht verschlüsselt")

    @Test
    @Config(qualifiers = "es-rES-w400dp-h1600dp")
    fun `the Spanish pair reads correctly and claims nothing about signing`() =
        assertThePairReadsCorrectly("no está cifrad")

    /**
     * One language, both sentences.
     *
     * The denial belongs to the plain sentence and to that one only. Two resources that had
     * been swapped would pass the drawing tests above and fail here.
     *
     * The last assertion is what lets [assertTheSentenceFitsTheGutter] measure the plain
     * sentence alone: the encrypted sentence is the plain one with the negation removed, so
     * it is shorter and its longest word is no longer. A block that fits the longer of the
     * two fits the other.
     */
    private fun assertThePairReadsCorrectly(denial: String) {
        val sentences = show(SourceKind.NETWORK_SHARE)
        val plain = sentences.plain.lowercase()
        val encrypted = sentences.encrypted.lowercase()

        assertTrue("the plain sentence reads \"$plain\"", plain.contains(denial))
        assertFalse("the encrypted sentence reads \"$encrypted\"", encrypted.contains(denial))
        for (claim in SIGNING) {
            assertFalse("the plain sentence mentions $claim", plain.contains(claim))
            assertFalse("the encrypted sentence mentions $claim", encrypted.contains(claim))
        }
        assertTrue(
            "\"$encrypted\" is ${encrypted.length} long, \"$plain\" is ${plain.length}",
            encrypted.length < plain.length,
        )
        assertTrue(
            "the encrypted sentence's longest word is ${longestWord(encrypted)}",
            longestWord(encrypted) <= longestWord(plain),
        )
    }

    private fun longestWord(sentence: String): Int =
        sentence.split(' ').maxOf { it.length }

    @Test
    @Config(qualifiers = "w320dp-h1600dp")
    fun `the sentence fits the narrowest window at the largest text size in English`() =
        assertTheSentenceFitsTheGutter()

    @Test
    @Config(qualifiers = "fr-rFR-w320dp-h1600dp")
    fun `the sentence fits the narrowest window at the largest text size in French`() =
        assertTheSentenceFitsTheGutter()

    @Test
    @Config(qualifiers = "de-rDE-w320dp-h1600dp")
    fun `the sentence fits the narrowest window at the largest text size in German`() =
        assertTheSentenceFitsTheGutter()

    @Test
    @Config(qualifiers = "es-rES-w320dp-h1600dp")
    fun `the sentence fits the narrowest window at the largest text size in Spanish`() =
        assertTheSentenceFitsTheGutter()

    private fun assertTheSentenceFitsTheGutter() {
        val sentences = show(SourceKind.NETWORK_SHARE, fontScale = LARGEST_TEXT)
        val bounds = compose.onNodeWithText(sentences.plain).getUnclippedBoundsInRoot()
        assertTrue(
            "the sentence was measured ${bounds.right - bounds.left} wide",
            bounds.right - bounds.left > Dp.Hairline,
        )
        assertTrue("the sentence starts at ${bounds.left}", bounds.left >= StoryArcSpace.gutter)
        assertTrue(
            "the sentence ends at ${bounds.right}, past ${WINDOW - StoryArcSpace.gutter}",
            bounds.right <= WINDOW - StoryArcSpace.gutter,
        )
    }

    private companion object {
        val SIGNING = listOf(
            "signed", "signing", "signé", "signature", "signiert", "signatur", "firmad", "firma",
        )

        val WINDOW = 320.dp

        const val LARGEST_TEXT = 2f
    }
}
