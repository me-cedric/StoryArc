package app.storyarc.core.playback

import android.app.PendingIntent
import android.net.Uri
import android.os.Looper
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.SimpleBasePlayer
import androidx.media3.common.util.UnstableApi
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture

/**
 * The read-aloud voice, as a media3 `Player`, so the voice lives behind [PlaybackService]'s
 * one `MediaLibrarySession`.
 *
 * Task 13.2. `audio-playback`, *One player for everything that speaks*: the shade, the lock
 * screen and a car draw a session, and a voice that posted a notification and a session of its
 * own was a second transport. [PlaybackService] seats this player while the voice holds the
 * session, and seats the decoder again when the voice ends. The voice then gets media3's own
 * notification, the lock screen, and a car row, exactly as a narrated file does.
 *
 * **It reads [PlaybackCentre], and drives it.** Everything it states is the centre's
 * [NowPlaying], and every command goes through the centre, so a pause from the shade writes the
 * position exactly as a pause from the app does. It names no engine, for the reason
 * [PlayerSource] gives.
 *
 * **One media item per part.** A car's next-track control then moves a chapter, as it does for
 * an audiobook (task 12.3). The shade's two outer buttons move a sentence — see
 * `PlaybackService.skipButton`. No item states a duration, and no seek inside an item is
 * offered, because a voice has no clock.
 *
 * @param reopen where a tap on the notification goes: back to the book, at the sentence being
 *   spoken. Built by the voice's own module, because this module cannot name the reader.
 */
@OptIn(UnstableApi::class)
internal class VoicePlayer(
    private val centre: PlaybackCentre,
    val reopen: PendingIntent?,
) : SimpleBasePlayer(Looper.getMainLooper()) {

    private var artwork: Uri? = null

    /**
     * Whether the request being handled comes from the app's own controller. Set by
     * [PlaybackService] when it seats this player.
     *
     * That controller drives a narrated file and never the voice: the app drives the voice
     * through [PlaybackCentre]. media3 runs a controller's commands one looper message later,
     * so a stop the app sent to the file just before the voice displaced it reaches the session
     * after the voice is seated. It must not reach the voice, or it ends the voice that has
     * just started.
     */
    var fromTheApp: () -> Boolean = { false }

    /** The cover the player drew, for the shade and the lock screen. */
    fun setArtwork(uri: Uri) {
        artwork = uri
        invalidateState()
    }

    /** The session changed: a sentence, a chapter, a pause, an ending. */
    fun changed() = invalidateState()

    override fun getState(): State {
        val playing = centre.nowPlaying ?: return State.Builder().build()
        val items = playing.parts.mapIndexed { index, part ->
            MediaItemData.Builder("${playing.publicationId}#$index")
                .setMediaItem(
                    MediaItem.Builder()
                        .setMediaId(playing.publicationId)
                        .setMediaMetadata(metadata(playing, part, index))
                        .build(),
                )
                .build()
        }
        return State.Builder()
            .setAvailableCommands(COMMANDS)
            .setPlaylist(items)
            .setCurrentMediaItemIndex(playing.partIndex.coerceIn(items.indices))
            .setContentPositionMs(0)
            .setPlaybackState(Player.STATE_READY)
            .setPlayWhenReady(playing.isPlaying, Player.PLAY_WHEN_READY_CHANGE_REASON_USER_REQUEST)
            .setPlaybackParameters(PlaybackParameters(playing.speed.rate.toFloat()))
            .build()
    }

    /**
     * What the shade and the lock screen say.
     *
     * `ebook-reader`: the controls "show the publication title", and the second line names the
     * chapter being spoken, or the author where the publication declares no navigation. The
     * voice's own module decides that line — see [PlayerSource.detail]. Another part states its
     * own title, so a car's queue lists the chapters.
     */
    private fun metadata(playing: NowPlaying, part: PlaybackPart, index: Int): MediaMetadata =
        MediaMetadata.Builder()
            .setTitle(playing.title)
            .setArtist(if (index == playing.partIndex) playing.detail else part.title.ifBlank { null })
            .setArtworkUri(artwork)
            .setIsBrowsable(false)
            .setIsPlayable(true)
            .setMediaType(MediaMetadata.MEDIA_TYPE_AUDIO_BOOK_CHAPTER)
            .build()

    override fun handleSetPlayWhenReady(playWhenReady: Boolean): ListenableFuture<*> {
        if (!fromTheApp() && playWhenReady != centre.nowPlaying?.isPlaying) centre.toggle()
        return Futures.immediateVoidFuture()
    }

    override fun handlePrepare(): ListenableFuture<*> = Futures.immediateVoidFuture()

    /** The shade's notification swiped away, or a controller's stop. The session ends. */
    override fun handleStop(): ListenableFuture<*> {
        if (!fromTheApp()) centre.stop()
        return Futures.immediateVoidFuture()
    }

    /** A chapter: a car's next or previous, or a chapter chosen from its queue. */
    override fun handleSeek(mediaItemIndex: Int, positionMs: Long, seekCommand: Int): ListenableFuture<*> {
        val parts = centre.nowPlaying?.parts.orEmpty()
        if (!fromTheApp() && mediaItemIndex in parts.indices) centre.seekToPart(mediaItemIndex)
        return Futures.immediateVoidFuture()
    }

    /**
     * A car chose the voice's own row. The voice is already speaking this book, so nothing is
     * loaded: `PlaybackService.onSetMediaItems` answers the choice, and the play that follows
     * carries on with the voice.
     */
    override fun handleSetMediaItems(
        mediaItems: MutableList<MediaItem>,
        startIndex: Int,
        startPositionMs: Long,
    ): ListenableFuture<*> = Futures.immediateVoidFuture()

    private companion object {
        /**
         * What a controller may ask of a voice. No seek inside an item and no seek by seconds,
         * because a voice has no clock: `audio-playback` asks a control that cannot work to be
         * absent rather than present and refusing.
         */
        val COMMANDS: Player.Commands = Player.Commands.Builder()
            .addAll(
                Player.COMMAND_PLAY_PAUSE,
                Player.COMMAND_PREPARE,
                Player.COMMAND_STOP,
                Player.COMMAND_SEEK_TO_DEFAULT_POSITION,
                Player.COMMAND_SEEK_TO_MEDIA_ITEM,
                Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM,
                Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM,
                Player.COMMAND_SEEK_TO_PREVIOUS,
                Player.COMMAND_SEEK_TO_NEXT,
                Player.COMMAND_SET_MEDIA_ITEM,
                Player.COMMAND_GET_CURRENT_MEDIA_ITEM,
                Player.COMMAND_GET_TIMELINE,
                Player.COMMAND_GET_METADATA,
            )
            .build()
    }
}
