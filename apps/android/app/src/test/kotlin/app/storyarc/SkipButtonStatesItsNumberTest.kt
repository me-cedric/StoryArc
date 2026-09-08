package app.storyarc

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * That a skip button still draws its own number, where a sighted reader can see it.
 *
 * `audio-playback` asks the interval to be "stated on the control itself". The number is a
 * `Text` under the glyph, and **no Compose test can see it**: the `Skip` composable wraps the
 * pair in `clearAndSetSemantics`, so the child semantics are cleared and the number never
 * reaches the semantics tree. Review measured the consequence — delete that `Text` and all
 * 2358 unit tests stay green, and a screenshot was the only proof.
 *
 * The gap predates the removal of the interval picker. It matters more now: the interval is
 * two constants, so the number under the glyph is the only place a reader learns it.
 *
 * **The glyph must stay unnumbered.** Material ships `Replay5`, `Replay10` and `Replay30` and
 * no `Replay15`, and a numbered glyph once drew "10" on a control that moved fifteen. That is
 * why the number is drawn as text beside an unnumbered arrow, and why this asserts both.
 *
 * Source text, and a tripwire rather than a proof: it says the number is drawn, never that it
 * was legible. `docs/designs/screenshots/android-skip-2026-09-08/` holds the frame.
 */
class SkipButtonStatesItsNumberTest {

    private val player = File("src/main/kotlin/app/storyarc/PlayerScreen.kt")

    private fun source(): String {
        assertTrue("${player.path} could not be read — has it moved?", player.isFile)
        return player.readText()
    }

    @Test
    fun `the number is drawn under the glyph`() {
        assertTrue(
            "The skip control no longer draws its seconds, so the interval is stated nowhere a" +
                " sighted reader can see it.",
            source().contains("stringResource(R.string.player_seconds, seconds)"),
        )
    }

    @Test
    fun `the glyph carries no number of its own`() {
        val text = source()

        // A numbered glyph is the defect this project already paid for once.
        for (numbered in listOf("Replay5", "Replay10", "Replay30", "Forward5", "Forward10", "Forward30")) {
            assertTrue(
                "$numbered draws a number into the glyph. Material has no Replay15, so a" +
                    " numbered glyph and a fifteen-second control cannot agree.",
                !text.contains("Icons.Filled.$numbered") && !text.contains("filled.$numbered"),
            )
        }
    }

    @Test
    fun `the pair is one control to a screen reader`() {
        assertTrue(
            "The skip control no longer collapses to one element, so a screen reader reads an" +
                " arrow and a loose number.",
            source().contains("clearAndSetSemantics { contentDescription = label }"),
        )
    }
}
