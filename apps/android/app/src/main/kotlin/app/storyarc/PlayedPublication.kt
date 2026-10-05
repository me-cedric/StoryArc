package app.storyarc

import app.storyarc.core.model.Publication
import app.storyarc.core.playback.NowPlaying

/**
 * The publication the full player should draw its cover and its format from, or null.
 *
 * `PlaybackHost.nowPlaying` carries an id and a title and nothing more, because
 * `:core:playback` has no business knowing what a [Publication] is. This is the app's half
 * of the answer, and it is two cases rather than one.
 *
 * **A book this app started** is [PlayingBook.following], matched against the session's own
 * id rather than trusted: a book the system resumed after the process died was started by
 * nothing here, and is drawn coverless rather than under the cover of whatever played last.
 *
 * **A publication being read aloud** is never followed, and that is deliberate — see
 * `carStartedBook`: pointing `reading-progress`' listening writer at a reflowable book
 * would write a part offset over its locator. So the library answers for it instead, and
 * the guard that keeps the first case honest is `isAudio`: media3 can resume an audiobook
 * with nobody watching and cannot resume anything else, so a **non-audio** publication on
 * the player is one this process is reading aloud and no other thing. Without this the
 * player drew the coverless well for every read-aloud session, while `audio-playback` asks
 * the full player to show "the cover, the publication, the chapter".
 */
internal fun playedPublication(
    playing: NowPlaying,
    following: Publication?,
    library: List<Publication>,
): Publication? = following?.takeIf { it.id == playing.publicationId }
    ?: library.firstOrNull { it.id == playing.publicationId && !it.format.isAudio }
