package app.storyarc.core.playback

import androidx.annotation.OptIn
import androidx.media3.common.ForwardingPlayer
import androidx.media3.common.Player
import androidx.media3.common.Tracks
import androidx.media3.common.util.UnstableApi

/**
 * Moves a car's next/previous press to the neighbouring chapter mark inside one file.
 *
 * `audio-playback`'s own control is a chapter move, and for a folder it already is one:
 * `Audiobook.layout` is `FILES`, so a part is a file and `BasePlayer.seekToNext` /
 * `seekToPrevious` carry across them for free. For `PartLayout.MARKS` the timeline holds one
 * window with the marks inside it, `hasNextMediaItem()` is false, and the press does
 * nothing — see [PlaybackService.LibraryCallback.onConnect]'s own comment for why building
 * this was deferred once already.
 *
 * **Why a wrapper, and why this shape.** `seekToNext` and `seekToPrevious` are `final` on
 * `BasePlayer`, so only a `ForwardingPlayer` can answer them differently. A `ForwardingPlayer`
 * registers every listener straight on the wrapped player by default — which is kept here,
 * deliberately, for every callback this class does not care about — so wrapping one changes
 * nothing about the shade, the lock screen or the notification that this file does not name.
 * The one callback it does care about is [onAvailableCommandsChanged]: a car reads whether
 * the chapter commands are available from the session's own `Player.Commands`, and the
 * wrapped player answers that honestly for a single window — "no, there is only one" — which
 * is correct for the player and wrong for this book. [offsets] is adopted from the same
 * `Tracks` callback [AudiobookSource.adoptChapters] reads, and every change to it re-sends an
 * augmented `Player.Commands` to each listener this class is holding, on top of whatever the
 * wrapped player already sent them.
 *
 * A folder is untouched: [offsets] stays empty whenever the current timeline holds more than
 * one window, [chapterSeekTarget] then answers null, and both methods fall back to the
 * wrapped player's own answer.
 */
@OptIn(UnstableApi::class)
internal class ChapterSeekingPlayer(player: Player) : ForwardingPlayer(player) {

    /** Where each chapter of the current single-window file starts. Empty for a folder. */
    private var offsets: List<Long> = emptyList()

    private val listeners = mutableSetOf<Player.Listener>()

    private val chapters = object : Player.Listener {
        override fun onTracksChanged(tracks: Tracks) {
            offsets = if (currentTimeline.windowCount == 1) {
                AudiobookChapters.offsets(ChapterMarks.of(tracks))
            } else {
                emptyList()
            }
            val commands = availableCommands
            listeners.toList().forEach { it.onAvailableCommandsChanged(commands) }
        }
    }

    init {
        player.addListener(chapters)
    }

    override fun addListener(listener: Player.Listener) {
        super.addListener(listener)
        listeners += listener
    }

    override fun removeListener(listener: Player.Listener) {
        super.removeListener(listener)
        listeners -= listener
    }

    override fun seekToNext() {
        val target = chapterSeekTarget(offsets, currentPosition, true, maxSeekToPreviousPosition)
        if (target == null) super.seekToNext() else seekTo(target)
    }

    override fun seekToPrevious() {
        val target = chapterSeekTarget(offsets, currentPosition, false, maxSeekToPreviousPosition)
        if (target == null) super.seekToPrevious() else seekTo(target)
    }

    override fun isCommandAvailable(command: Int): Boolean =
        if (isChapterCommand(command) && offsets.size > 1) true else super.isCommandAvailable(command)

    override fun getAvailableCommands(): Player.Commands {
        val base = super.getAvailableCommands()
        if (offsets.size <= 1) return base
        return base.buildUpon()
            .add(Player.COMMAND_SEEK_TO_NEXT)
            .add(Player.COMMAND_SEEK_TO_PREVIOUS)
            .build()
    }

    private fun isChapterCommand(command: Int) =
        command == Player.COMMAND_SEEK_TO_NEXT || command == Player.COMMAND_SEEK_TO_PREVIOUS
}

/**
 * Where a chapter move inside one file lands, or null to fall back to the player's own
 * next/previous: a folder, a file with at most one mark, or a press past either end.
 *
 * Pure, so the mark a press lands on is a plain JVM test rather than code only a real
 * `ExoPlayer` and a decoded container can exercise. [ChapterSeekingPlayer] is the one caller.
 *
 * **Back restarts the chapter first.** A press more than [maxSeekToPreviousMillis] into a
 * chapter goes to the start of that chapter, and only a press nearer its start goes to the
 * chapter before. `BasePlayer.seekToPrevious` does the same with the files of a folder, so a
 * car's back button means one thing for both layouts.
 *
 * @param offsets where each chapter starts, index-aligned with [AudiobookChapters.offsets].
 * @param maxSeekToPreviousMillis the player's own `maxSeekToPreviousPosition`.
 */
internal fun chapterSeekTarget(
    offsets: List<Long>,
    positionMillis: Long,
    forward: Boolean,
    maxSeekToPreviousMillis: Long,
): Long? {
    if (offsets.size <= 1) return null
    val current = AudiobookChapters.partAt(offsets, positionMillis)
    val intoChapter = positionMillis - offsets[current]
    if (!forward && intoChapter > maxSeekToPreviousMillis) return offsets[current]
    val target = if (forward) current + 1 else current - 1
    return offsets.getOrNull(target)
}
