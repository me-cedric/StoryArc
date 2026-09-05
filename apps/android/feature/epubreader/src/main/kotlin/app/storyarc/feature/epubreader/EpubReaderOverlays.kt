package app.storyarc.feature.epubreader

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.playback.SpokenAudio
import app.storyarc.core.playback.sentence
import kotlinx.coroutines.launch

/**
 * What is over the page and is not the chrome.
 *
 * **Why these are not a third revealed control.** `comic-reader`'s count is about what a tap
 * reveals. The return offer is armed by a long jump the reader just made and disarmed by
 * taking it; the transport exists only while a voice is speaking, and `read-aloud` requires
 * it to be reachable while the reader is looking at the page; the word about a stopped voice
 * is armed by opening this book and leaves on its own. None arrives with the chrome and none
 * survives the thing that armed it — which is why they are in their own file rather than in
 * `EpubChrome.kt`, whose button count is a guarded number.
 *
 * All sit above the foot of the page. The word about the voice sits above the return offer,
 * which sits above the transport: what just happened somewhere else, then where the reader
 * just was, then what the voice is doing now.
 */
@Composable
internal fun EpubReaderOverlays(
    /** Whether a jump has left somewhere worth going back to. */
    canReturn: Boolean,
    onReturn: () -> Unit,
    /** Whether the transport belongs on screen: speaking, or paused mid-book. */
    isReadingAloud: Boolean,
    isSpeaking: Boolean,
    onToggleReadAloud: () -> Unit,
    onSkipSentence: (Boolean) -> Unit,
    onStopReadAloud: () -> Unit,
    modifier: Modifier = Modifier,
    /**
     * The authority that arms the word a displaced voice owes. The app's one, except in a test
     * — and a parameter here rather than a read of the singleton inside, so a test can arm it.
     */
    spokenAudio: SpokenAudio = SpokenAudio.shared,
) {
    val palette = LocalStoryArcPalette.current
    val snackbars = remember { SnackbarHostState() }
    VoiceStoppedWord(spokenAudio, snackbars)

    Column(
        // Clear of the two-control capsule, which sits at the very foot of the page.
        modifier = modifier
            .fillMaxSize()
            .safeDrawingPadding()
            .padding(bottom = StoryArcSpace.xxl * 2),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Bottom,
    ) {
        // `ebook-reader`, *Opening a different publication*: "the listener is told once that
        // the voice stopped, rather than discovering it by silence". The word lands over this
        // page because this is where the listener is looking — see [VoiceStoppedWord].
        SnackbarHost(snackbars)

        // `ebook-reader`: "a longer jump navigates with a control to return to where they
        // were". It names the page rather than saying "Back", because by the time a reader
        // notices they have lost their place they no longer remember what it was.
        if (canReturn) {
            Surface(
                shape = RoundedCornerShape(StoryArcRadius.lg),
                color = palette.surfaceRaised,
                onClick = onReturn,
                modifier = Modifier.padding(bottom = StoryArcSpace.sm),
            ) {
                Text(
                    text = stringResource(R.string.epub_return),
                    style = MaterialTheme.typography.labelLarge,
                    color = palette.accent,
                    modifier = Modifier.padding(
                        horizontal = StoryArcSpace.md,
                        vertical = StoryArcSpace.xs,
                    ),
                )
            }
        }

        if (isReadingAloud) {
            ReadAloudBar(
                isSpeaking = isSpeaking,
                onPrevious = { onSkipSentence(false) },
                onToggle = onToggleReadAloud,
                onNext = { onSkipSentence(true) },
                onStop = onStopReadAloud,
            )
        }
    }
}

/**
 * Shows the word a displaced voice owes, once, as a snackbar — and takes it by showing it.
 *
 * **Told once is the take.** [SpokenAudio.takeVoiceStopped] spends the notice the moment this
 * screen reads it, so a second composition — the same page redrawn, or a return to it — finds
 * nothing. A `Snackbar` because that is this codebase's word for a brief, non-modal notice
 * that leaves on its own; Material's host also marks it a polite live region, which is what
 * has TalkBack say the sentence once.
 *
 * **Collected with the lifecycle, and that is load-bearing.** Two screens can be composed at
 * the same moment a voice is displaced — this activity behind, the player in front — and only
 * the one the listener is looking at may take the word. `collectAsStateWithLifecycle` stops
 * collecting below `STARTED`, so a stopped activity never sees the notice pending and cannot
 * spend it on a page nobody is looking at.
 *
 * The snackbar is shown from a scope of its own rather than inside the effect: taking the
 * notice changes the collected value, which would restart an effect keyed on it and cancel
 * the very snackbar it had just begun to show.
 *
 * `PlayerScreen.kt` carries the same effect over the player, because a feature module and the
 * app module cannot share a composable without one depending on the other; the rule behind
 * both is `VoiceStoppedNotice`, in `:core:playback`, and asserted there.
 */
@Composable
private fun VoiceStoppedWord(spokenAudio: SpokenAudio, snackbars: SnackbarHostState) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val owed by spokenAudio.voiceStopped.collectAsStateWithLifecycle()
    LaunchedEffect(owed) {
        if (!owed.isPending) return@LaunchedEffect
        val sentence = spokenAudio.takeVoiceStopped().sentence(context) ?: return@LaunchedEffect
        scope.launch { snackbars.showSnackbar(sentence) }
    }
}
