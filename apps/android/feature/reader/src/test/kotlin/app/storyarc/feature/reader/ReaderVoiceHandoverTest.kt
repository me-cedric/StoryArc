package app.storyarc.feature.reader

import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.playback.SpokenAudio
import java.io.File
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * D18: opening a comic or a PDF ends a voice already speaking — a narrated audiobook or an
 * EPUB being read aloud — the way `ebook-reader` requires of any publication opening over one.
 *
 * **Where this sits beside the seam it depends on.** `SpokenAudioTest` pins
 * [SpokenAudio.silence] itself — what counts as a voice, what the notice says, that it arms
 * once. This pins only the wiring this decision adds: that opening this reader asks before
 * anything else happens. A [SpokenAudio] of this test's own, never `.shared`, so this suite
 * cannot see another suite's session.
 *
 * **Proved able to fail**, per AGENTS.md §5: removing the `speaker.silence(...)` line from
 * `ReaderViewModel.open` failed *Opening a comic ends a voice already speaking* by name — the
 * fake speaker's `endSpeaking()` was never called and the notice stayed unarmed. Reverted.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ReaderVoiceHandoverTest {

    /** A voice with nowhere for its words to go — this suite only needs it to exist and stop. */
    private class FakeVoice(title: String) : SpokenAudio.Speaker {
        var ended = false
        override var speaking: SpokenAudio.Spoken? = SpokenAudio.Spoken(id = "the-long-field", title = title)
            private set
        override val kind: SpokenAudio.Kind = SpokenAudio.Kind.VOICE
        override fun endSpeaking() {
            ended = true
            speaking = null
        }
    }

    private fun fixture(name: String): File {
        val module = System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error("$MODULE_DIRECTORY is unset. Run this test through Gradle.")
        val file = File(module, "$CORPUS/$name").canonicalFile
        if (!file.isFile) error("$name is not under ${module.absolutePath}/$CORPUS -- has it moved?")
        return file
    }

    private fun comicModel(speaker: SpokenAudio): ReaderViewModel {
        val file = fixture("refused.cb7")
        return ReaderViewModel(
            publication = Publication(
                identity = PublicationIdentity(normalizedPath = file.absolutePath),
                format = PublicationFormat.CB7,
                displayTitle = "A Quiet Harbour",
                origin = MetadataOrigin.INFERRED,
            ),
            resolver = RuntimeEnvironment.getApplication().contentResolver,
            path = file.absolutePath,
            speaker = speaker,
        )
    }

    @Test
    fun `opening a comic ends a voice already speaking, and tells the listener once`() {
        val speaker = SpokenAudio()
        val voice = FakeVoice("The Long Field")
        speaker.register(voice)

        runBlocking { comicModel(speaker).open(256) }

        assertTrue("The voice that was speaking should have ended.", voice.ended)
        assertEquals("The Long Field", speaker.takeVoiceStopped().title)
    }

    @Test
    fun `opening a comic while nothing speaks owes no word`() {
        val speaker = SpokenAudio()

        runBlocking { comicModel(speaker).open(256) }

        assertNull(speaker.takeVoiceStopped().title)
    }

    private companion object {
        /** Set by this module's `build.gradle.kts`, from its own `projectDir`. */
        const val MODULE_DIRECTORY = "storyarc.reader.projectDir"
        const val CORPUS = "../../../../packages/test-fixtures/comics"
    }
}
