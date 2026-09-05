package app.storyarc.core.playback

import android.content.Context

/**
 * The one sentence a surface shows for a [VoiceStoppedNotice], or null when nothing is owed.
 *
 * Worded here rather than in either surface that draws it, because two surfaces draw it — the
 * EPUB reader over its page and the player the shelf opens — and `read-aloud-beyond-the-reader`
 * 5.5 allows this change exactly one new key. One key lives in one module's resources, and this
 * module is the one both surfaces already depend on; `:core:designsystem` deliberately ships no
 * strings, so it could not be there. iOS keeps the same sentence on `VoiceStoppedNotice.sentence`
 * in `Playback`'s catalogue for the same reason.
 *
 * An extension in its own file rather than a member, so [VoiceStoppedNotice] stays the pure
 * value both host suites assert against — it needs no `Context`, and this does.
 */
fun VoiceStoppedNotice.sentence(context: Context): String? =
    title?.let { context.getString(R.string.playback_voice_stopped, it) }
