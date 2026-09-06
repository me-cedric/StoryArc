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
 * connection is encrypted". The sentence lived only in the add-share sheet, which a reader sees
 * once, before the source exists.
 *
 * **The sentence names encryption and never signing, and that is a decision rather than an
 * omission.** ADR-0016 refuses a signing line on iOS -- that client verifies no response and
 * cannot answer the question, and "the app does not explain its own weaknesses to the reader".
 * jcifs-ng can answer it, and the Android add-share sheet says so; this screen is drawn the same
 * way on both platforms, so it states the transport and the encryption alone. A signed session
 * and an unsigned one read alike here, which the last two tests assert in all four locales.
 *
 * **The sentence denies encryption, and the denial is what is asserted.** Both clients hardcode
 * `isEncrypted = false`, so the screen states a constant rather than reading the session, and
 * ADR-0016 records why that is where this stands. The day item 1 of that ADR's *What would change
 * this* lands, the four sentences become false and these tests fail by name, in whichever locale
 * was edited first.
 *
 * Composed rather than asserted through a helper, for the reason `SourceProgressNoteTest`
 * composes: a test of the predicate alone stays green when the row is deleted from the screen.
 */
@RunWith(RobolectricTestRunner::class)
// Robolectric ships an image per API level and has none for 37, so it cannot be handed the
// module's target. 34 is inside its range and above the minimum this app supports, and the
// question here -- whether one sentence is drawn -- has no API level in it. The window is tall
// because the screen scrolls: a sentence below the fold is present and not displayed, and that
// distinction would make this test report the wrong thing.
@Config(sdk = [34], qualifiers = "w400dp-h1600dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class SourceTransportNoteTest {

    @get:Rule
    val compose = createComposeRule()

    /**
     * The screen as `SettingsScreen` reaches it, for one source.
     *
     * Returns the sentence so the assertions look for the shipped string in the locale
     * Robolectric was configured with, rather than for a copy of it written into this file.
     */
    private fun show(source: Source, fontScale: Float = 1f): String {
        var sentence = ""
        compose.setContent {
            sentence = stringResource(R.string.sources_detail_transport)
            CompositionLocalProvider(
                LocalDensity provides Density(density = 1f, fontScale = fontScale),
            ) {
                StoryArcTheme {
                    SourceDetailScreen(
                        source = source,
                        diagnosis = SourceDiagnosis.of(
                            source,
                            itemCount = 3,
                            downloads = emptyList(),
                        ),
                        onAction = {},
                        onBack = {},
                    )
                }
            }
        }
        compose.waitForIdle()
        return sentence
    }

    private fun show(
        kind: SourceKind,
        state: SourceConnectionState = SourceConnectionState.Connected,
        fontScale: Float = 1f,
    ): String = show(Source(displayName = "Fixture", kind = kind, state = state), fontScale)

    @Test
    fun `a share on the network states its transport`() {
        compose.onNodeWithText(show(SourceKind.NETWORK_SHARE)).assertIsDisplayed()
    }

    @Test
    fun `a folder states none, because a folder is a disk`() {
        compose.onNodeWithText(show(SourceKind.LOCAL_FOLDER)).assertDoesNotExist()
    }

    @Test
    fun `an OPDS catalogue states none, because it is reached over HTTP`() {
        compose.onNodeWithText(show(SourceKind.OPDS_CATALOG)).assertDoesNotExist()
    }

    @Test
    fun `kavita states none, for the same reason`() {
        compose.onNodeWithText(show(SourceKind.KAVITA_SERVER)).assertDoesNotExist()
    }

    // A signed session and an unsigned one read alike, because signing never reaches this
    // screen. The screen is handed a `Source` and a `SourceDiagnosis`, and neither carries what
    // the session negotiated, so the sentence cannot vary with it. What a live session does
    // reach the screen through is the connection state, and that moves the sentence no more
    // than signing does.

    @Test
    fun `a refused credential leaves the sentence alone`() {
        val sentence = show(
            SourceKind.NETWORK_SHARE,
            SourceConnectionState.Unauthorized("The password was refused."),
        )
        compose.onNodeWithText(sentence).assertIsDisplayed()
    }

    @Test
    fun `an unreachable share leaves the sentence alone`() {
        val sentence = show(SourceKind.NETWORK_SHARE, SourceConnectionState.Unreachable(0L))
        compose.onNodeWithText(sentence).assertIsDisplayed()
    }

    @Test
    fun `every locale states the connection is not encrypted, and none claims signing`() {
        // English here, and the other three below: Robolectric resolves one locale per test.
        assertTheSentenceDeniesEncryptionAndSaysNothingOfSigning("not encrypted")
    }

    @Test
    @Config(qualifiers = "fr-rFR-w400dp-h1600dp")
    fun `the French sentence denies encryption and claims no signing`() =
        assertTheSentenceDeniesEncryptionAndSaysNothingOfSigning("pas chiffr")

    @Test
    @Config(qualifiers = "de-rDE-w400dp-h1600dp")
    fun `the German sentence denies encryption and claims no signing`() =
        assertTheSentenceDeniesEncryptionAndSaysNothingOfSigning("nicht verschlüsselt")

    @Test
    @Config(qualifiers = "es-rES-w400dp-h1600dp")
    fun `the Spanish sentence denies encryption and claims no signing`() =
        assertTheSentenceDeniesEncryptionAndSaysNothingOfSigning("no está cifrad")

    /**
     * The claim a reader is owed, and the words ADR-0016 refuses.
     *
     * **The negation is matched, not the word alone.** An earlier form of this test asked only
     * whether the sentence carried the word for "encrypted", so *The connection is encrypted.*
     * satisfied it. That is the edit someone will make the day a client negotiates SMB 3, and it
     * is the edit that lands in one locale before the other three. The polarity is the whole of
     * the claim, so the polarity is what is pinned.
     *
     * Every refused token is matched against every locale: a French word has no business in the
     * German sentence either, and the signing half is a promise this app makes in none of the
     * four.
     */
    private fun assertTheSentenceDeniesEncryptionAndSaysNothingOfSigning(denial: String) {
        val sentence = show(SourceKind.NETWORK_SHARE).lowercase()
        assertTrue("the sentence reads \"$sentence\"", sentence.contains(denial))
        for (claim in SIGNING) {
            assertFalse("the sentence mentions $claim", sentence.contains(claim))
        }
    }

    // The sentence has to wrap, so `design.md` sections 3 and 10 -- every screen survives the
    // largest accessibility text size with "no clipping" -- land on it. All four shipped
    // locales, because the length that decides the wrap is different in each.

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
        val sentence = show(SourceKind.NETWORK_SHARE, fontScale = LARGEST_TEXT)
        val bounds = compose.onNodeWithText(sentence).getUnclippedBoundsInRoot()
        // Unclipped bounds, so a sentence laid out past the edge reports where it really went
        // rather than where the window cut it. The screen pads its scrolling column by the
        // gutter on every side, so those two edges are the ones a wrap has to respect.
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
        /** The words ADR-0016 keeps off this screen, in all four shipped languages. */
        val SIGNING = listOf(
            "signed", "signing", "signé", "signature", "signiert", "signatur", "firmad", "firma",
        )

        /** The narrowest window Android's compact width class allows, and so the floor. */
        val WINDOW = 320.dp

        /** The largest font scale Android's accessibility settings offer. */
        const val LARGEST_TEXT = 2f
    }
}
