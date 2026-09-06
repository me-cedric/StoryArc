package app.storyarc

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.cover.CoverlessWell
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.model.Publication

/**
 * How large the cover is asked for. The same 512 the shelves ask for, so a book whose cover
 * the library has already drawn is answered from the cache rather than decoded again.
 */
private const val ARTWORK_PIXELS = 512

/** How wide the artwork may be: iOS's `PlayerArtwork` is 320 pt, and the two players agree. */
private val ARTWORK_MAX_WIDTH = 320.dp

/**
 * The player's artwork: the cover, or the well every other surface draws when there is none.
 *
 * `audio-playback`, *The full player*: it "shows the cover, the publication, the chapter …".
 * *A publication with no cover*: the player "draws the same coverless treatment every other
 * surface draws … rather than a treatment of the player's own", and "the system's own media
 * controls are given that same artwork rather than a second one". Until this file the Android
 * player drew nothing above its chapter name — not a cover, not a well, not a glyph — which
 * `docs/designs/screenshots/android-player-2026-09-04/android-player-full.png` shows, and the
 * design review of 2026-09-06 named as its finding 8.
 *
 * **The well is [CoverlessWell] and not a shape of this file's own.** It is the composable the
 * library shelf, Downloads, Home's cards and the series shelf all draw, in `:core:designsystem`
 * so that `:app` can call it; a second implementation here would be the drift its own header
 * warns about. It takes this platform's two parameters, the title and the format, exactly as
 * `DownloadsParts.kt` hands them over — the format-symbol treatment iOS's well adopted is
 * `audiobooks-and-playback` §4.4b's `:core:designsystem` work, recorded there, and is not
 * decided by a player.
 *
 * **A square rather than 2:3, for the reason iOS's `PlayerArtwork` gives.** An audiobook's
 * artwork is square everywhere a listener has seen one, and the picture below is what the
 * shade and a car display are handed. The well fills whatever shape it is given; a cover is
 * letterboxed onto `surfaceSunken` inside the square rather than cropped, which is the rule
 * every cover cell in this app already follows.
 *
 * **Silent to a screen reader, on both branches.** The top bar states the title and the
 * chapter list states the parts; an `Image` with no description and a well that clears its own
 * semantics add nothing, so TalkBack names the book once. `PlayerSemanticsTest` pins that.
 *
 * **The same picture goes to the media session**, when a sink is given: the drawn pixels are
 * recorded into a graphics layer and handed to [onArtwork] once the artwork has settled — the
 * cover has arrived, or the answer is that there is none — so the notification and the lock
 * screen show what the player shows rather than a second treatment kept in step by hand. iOS
 * renders the same view to PNG for `MPMediaItemPropertyArtwork` for the same reason. Null in a
 * test, where there is no session to hand anything to and no renderer to hand it from.
 *
 * @param title what the publication is called — the well's stand-in for artwork.
 * @param publication the publication being played, or null when the app does not know it: a
 *   book put back on the air by the system's own carousel after the process died reaches the
 *   player with an id nothing in the app has seen. The well then names no format.
 * @param cover where artwork comes from, as a function rather than a view model, so a test can
 *   hand over a cover or the absence of one in a line. `OnDeviceCover` takes its cover the
 *   same way for the same reason.
 */
@Composable
internal fun PlayerArtwork(
    title: String,
    publication: Publication?,
    cover: suspend (Publication, Int) -> Bitmap?,
    onArtwork: ((Bitmap) -> Unit)?,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current
    var art by remember(publication?.id) { mutableStateOf<Bitmap?>(null) }
    // Whether the cover question has been answered, either way. The picture handed to the
    // session waits for this, or the lock screen would get the well for a book that has a
    // cover arriving a frame later.
    var isResolved by remember(publication?.id) { mutableStateOf(publication == null) }
    LaunchedEffect(publication?.id) {
        val asked = publication ?: return@LaunchedEffect
        art = cover(asked, ARTWORK_PIXELS)
        isResolved = true
    }

    val layer = rememberGraphicsLayer()
    // Recorded only where something will read it. A test composes this with no sink and no
    // renderer worth the name, and a layer nobody reads is a layer that need not exist.
    val recorded = if (onArtwork == null) {
        Modifier
    } else {
        Modifier.drawWithContent {
            layer.record { this@drawWithContent.drawContent() }
            drawLayer(layer)
        }
    }

    Box(modifier = modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        Box(
            modifier = Modifier
                .widthIn(max = ARTWORK_MAX_WIDTH)
                .fillMaxWidth()
                .aspectRatio(1f)
                .then(recorded)
                .clip(RoundedCornerShape(StoryArcRadius.lg))
                .background(palette.surfaceSunken),
        ) {
            val drawn = art
            if (drawn != null) {
                Image(
                    bitmap = drawn.asImageBitmap(),
                    // The top bar names the book. A description here would name it twice.
                    contentDescription = null,
                    contentScale = ContentScale.Fit,
                    modifier = Modifier.fillMaxSize(),
                )
            } else {
                CoverlessWell(title = title, format = publication?.format?.displayName)
            }
        }
    }

    if (onArtwork != null) {
        LaunchedEffect(isResolved, art) {
            if (!isResolved) return@LaunchedEffect
            // Two frames: one for the resolved artwork to compose, one for it to be drawn
            // into the layer. Reading the layer before it has recorded anything is an empty
            // picture on the lock screen.
            withFrameNanos { }
            withFrameNanos { }
            val picture = runCatching { layer.toImageBitmap() }.getOrNull() ?: return@LaunchedEffect
            onArtwork(picture.asAndroidBitmap())
        }
    }
}
