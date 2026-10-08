package app.storyarc

import android.graphics.Bitmap
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.key
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.dp
import app.storyarc.core.model.Publication

/**
 * The player's artwork, drawn out of sight so the system's own controls have it before anyone
 * opens the player.
 *
 * `audiobooks-and-playback` task 4.4b, `audio-playback`'s *A publication with no cover*: the
 * shade, the lock screen and a car display are "given that same artwork rather than a second
 * one". The picture was handed over only while [PlayerScreen] was composed, so a book started
 * from a car, or left in the compact bar before the screen drew, had none. This composes the
 * very same [PlayerArtwork] — the well, or the cover, under the app's own theme — and sends its
 * pixels through [onArtwork] exactly as the screen does. It is a second *place* that draws the
 * picture and never a second *treatment*, which is the whole of the requirement.
 *
 * **Out of sight by position, not by transparency.** A zero-size box holds the artwork at a
 * large negative offset: it is laid out and drawn into its graphics layer like any other node,
 * which is what [PlayerArtwork] records the picture from, and it is never inside the window. A
 * zero alpha would have the layer skipped by whatever optimisation reads it as invisible.
 * Cleared of semantics, so TalkBack has nothing to land on.
 *
 * Composed by [AppShell] only while the player is *not* on screen: when it is, the screen's own
 * [PlayerArtwork] sends the same picture, and two writers of one file are one too many.
 *
 * @param publication the book being played, or null when none is, which draws nothing.
 */
@Composable
internal fun SessionArtwork(
    publication: Publication?,
    cover: suspend (Publication, Int) -> Bitmap?,
    onArtwork: (Bitmap) -> Unit,
) {
    if (publication == null) return
    key(publication.id) {
        Box(Modifier.size(0.dp).offset(x = OUT_OF_SIGHT).clearAndSetSemantics {}) {
            PlayerArtwork(
                title = publication.displayTitle,
                publication = publication,
                cover = cover,
                onArtwork = onArtwork,
                modifier = Modifier.requiredSize(ARTWORK_MAX_WIDTH),
            )
        }
    }
}

/** How far left of the window the artwork is laid out. */
private val OUT_OF_SIGHT = (-4000).dp
