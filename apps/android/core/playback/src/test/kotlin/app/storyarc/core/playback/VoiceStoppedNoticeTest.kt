package app.storyarc.core.playback

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Being told **once** that the voice stopped.
 *
 * `ebook-reader`, *Opening a different publication*:
 *
 * > **AND** the listener is told once that the voice stopped, rather than discovering it by
 * > silence
 *
 * The clause had no owner until 2026-09-05. It needs a sentence never written on either
 * platform, and `read-aloud-beyond-the-reader` task 5.5's rule sends every new string to the
 * vocabulary slice — whose scope, as drafted, promotes *existing* literals and does not take a
 * new one. The owner placed it here: this change ships the one key with its four translations.
 * See that task list's 1.4 and 5.5.
 *
 * **What is asserted here is the arithmetic, not the sentence.** `once` is the load-bearing
 * word, and it is the only part of this that a screen cannot be trusted with: a flag left
 * standing is shown again on every return, and nothing about that looks wrong in a screenshot.
 * iOS pins the same table in `VoiceStoppedNoticeTests`, case for case; `SpokenAudioTest` pins
 * where the value is armed.
 */
class VoiceStoppedNoticeTest {

    @Test
    fun `nothing is owed before anything happens`() {
        assertFalse(VoiceStoppedNotice.NONE.isPending)
        assertNull(VoiceStoppedNotice.NONE.title)
    }

    @Test
    fun `displacing a voice owes the listener a word naming the book`() {
        val owed = VoiceStoppedNotice.displacing(aVoice = true, title = "The Long Field")
        assertTrue(owed.isPending)
        assertEquals("The Long Field", owed.title)
    }

    /**
     * A narrator that stops when you open another book is an event a reader already
     * understands. `ebook-reader`'s scenario says *the voice*, and only the voice.
     */
    @Test
    fun `displacing a narrated book owes nothing`() {
        val owed = VoiceStoppedNotice.displacing(aVoice = false, title = "Sea Room")
        assertEquals(VoiceStoppedNotice.NONE, owed)
        assertFalse(owed.isPending)
        assertNull(owed.title)
    }

    /**
     * The whole of *once*. The surface that shows the word is not the surface that armed it,
     * and on a return to the screen it is the only one still running — so the notice has to be
     * spent by being given rather than by being remembered.
     */
    @Test
    fun `told once - taking the notice leaves nothing to tell`() {
        val owed = VoiceStoppedNotice.displacing(aVoice = true, title = "The Long Field")
        assertTrue(owed.isPending)
        assertFalse(owed.taken().isPending)
        assertNull(owed.taken().title)
    }

    @Test
    fun `returning again still finds nothing to tell`() {
        val given = VoiceStoppedNotice.displacing(aVoice = true, title = "The Long Field").taken()
        assertFalse(given.taken().isPending)
        assertEquals(VoiceStoppedNotice.NONE, given.taken().taken())
    }

    /**
     * One word per stopping, not one word ever. A listener whose voice is displaced a second
     * time has a second thing to be told about — and it is about the second book.
     */
    @Test
    fun `a second displacement owes a second word`() {
        val given = VoiceStoppedNotice.displacing(aVoice = true, title = "The Long Field").taken()
        assertFalse(given.isPending)
        assertEquals(
            "Harbour Lights 02",
            VoiceStoppedNotice.displacing(aVoice = true, title = "Harbour Lights 02").title,
        )
    }
}
