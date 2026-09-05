package app.storyarc

import androidx.compose.runtime.Composable
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.playback.NowPlaying
import app.storyarc.core.playback.PlaybackDuration
import app.storyarc.core.playback.PlaybackPart
import app.storyarc.core.playback.PlaybackSession
import app.storyarc.core.playback.PlaybackSpeed
import app.storyarc.core.playback.SpokenAudio
import app.storyarc.core.playback.VoiceStoppedNotice
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The surface's half of being told **once** that the voice stopped.
 *
 * `ebook-reader`, *Opening a different publication*:
 *
 * > **AND** the listener is told once that the voice stopped, rather than discovering it by
 * > silence
 *
 * `SpokenAudioTest` pins where the word is armed and that taking it spends it. What it cannot
 * pin is that a screen *does* take it — a screen that merely read the notice would show it on
 * every return, and nothing about that looks wrong in a screenshot. So this composes the
 * player over an authority with a displaced voice and asserts three things: the sentence is
 * on screen, it names the book that went quiet, and the authority has nothing left to say. A
 * second player composed over the same authority then finds nothing, which is the whole of
 * *once* from the listener's side.
 *
 * The player rather than the EPUB reader's overlays because `:feature:epubreader` has no
 * Compose test rule and this module does; the two surfaces carry the same effect, documented
 * against each other in `PlayerScreen.kt` and `EpubReaderOverlays.kt`.
 *
 * Robolectric with `GraphicsMode.NATIVE`, for the reason `PlayerSemanticsTest` sets out.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], qualifiers = "w360dp-h740dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class VoiceStoppedWordTest {

    @get:Rule
    val compose = createComposeRule()

    /** A voice that was reading *The Peregrine*, as the authority sees it. */
    private class Voice(var speakingNow: String?) : SpokenAudio.Speaker {
        override val speaking: SpokenAudio.Spoken?
            get() = speakingNow?.let { SpokenAudio.Spoken(it, "The Peregrine") }
        override val kind: SpokenAudio.Kind = SpokenAudio.Kind.VOICE
        override fun endSpeaking() { speakingNow = null }
    }

    /** A narrator about to start *Sea Room*. */
    private class Narrator : SpokenAudio.Speaker {
        override val speaking: SpokenAudio.Spoken? = null
        override val kind: SpokenAudio.Kind = SpokenAudio.Kind.NARRATOR
        override fun endSpeaking() = Unit
    }

    /** An authority in the state opening an audiobook over a voice leaves it in. */
    private fun displacedVoice(): SpokenAudio = SpokenAudio().apply {
        register(Voice("the-peregrine"))
        register(Narrator())
        claim("sea-room", by = Narrator())
    }

    private val playing = NowPlaying(
        publicationId = "sea-room",
        title = "Sea Room",
        parts = listOf(PlaybackPart("The Shiants", PlaybackDuration.Known(300_000))),
        partIndex = 0,
        offsetMillis = 42_000,
        session = PlaybackSession().started(),
        speed = PlaybackSpeed.of(1.0),
    )

    @Composable
    private fun Player(spokenAudio: SpokenAudio) {
        StoryArcTheme {
            PlayerScreen(
                playing = playing,
                onToggle = {},
                onSkip = {},
                onSeek = {},
                onChooseChapter = {},
                onSpeed = {},
                sleep = null,
                onSleep = {},
                onBack = {},
                spokenAudio = spokenAudio,
            )
        }
    }

    @Test
    fun `the player says once that the voice stopped, naming the book, and takes the word`() {
        val audio = displacedVoice()

        compose.setContent { Player(audio) }

        compose.onNodeWithText("Stopped reading “The Peregrine” aloud.").assertIsDisplayed()
        assertEquals(VoiceStoppedNotice.NONE, audio.voiceStopped.value)
    }

    /** A return to the player — a fresh composition over the same authority — finds nothing. */
    @Test
    fun `a second player over a word already given finds nothing to say`() {
        val audio = displacedVoice()
        audio.takeVoiceStopped()

        compose.setContent { Player(audio) }

        compose.onAllNodesWithText("Stopped reading “The Peregrine” aloud.").assertCountEquals(0)
    }

    @Test
    fun `a player over a displaced narrator says nothing`() {
        val audio = SpokenAudio().apply {
            register(Voice(null))
            register(
                object : SpokenAudio.Speaker {
                    override val speaking: SpokenAudio.Spoken? = SpokenAudio.Spoken("dune", "Dune")
                    override val kind: SpokenAudio.Kind = SpokenAudio.Kind.NARRATOR
                    override fun endSpeaking() = Unit
                },
            )
            silence(toSpeak = "sea-room")
        }

        compose.setContent { Player(audio) }

        compose.onAllNodesWithText("aloud.", substring = true).assertCountEquals(0)
    }
}
