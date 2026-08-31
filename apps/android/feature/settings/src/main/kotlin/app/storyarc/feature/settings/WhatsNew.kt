package app.storyarc.feature.settings

import android.content.Context
import android.content.SharedPreferences
import androidx.annotation.StringRes
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.LibraryBooks
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.FormatSize
import androidx.compose.material.icons.filled.Shield
import androidx.compose.ui.graphics.vector.ImageVector

/**
 * What changed in a version, and whether this launch is the one that should say so.
 *
 * `settings-and-about`: "The app SHALL tell a reader what changed, once, after it has been
 * updated, and SHALL never let that get in the way of reading."
 *
 * **The log is a value compiled into the app, not a document fetched from anywhere.** The
 * spec's offline scenario — "the screen appears in full, because what changed ships with the
 * app and is never fetched" — is held structurally by that: there is no URL here, no parser
 * and nothing to be unreachable. Only the *words* are a resource, in this module's
 * `strings.xml`, which is how they exist in the four shipped languages and how a missing
 * translation fails `lint` rather than reaching a reader. iOS's `WhatsNew.swift` is the same
 * value over a string catalogue.
 */
object WhatsNew {

    /**
     * Every release worth a word, newest first — which is the order About lists them in.
     *
     * **0.1.0 is a first entry that had a great deal to catch up on.** The app shipped page
     * curl, five typefaces, six reading themes, OPDS, Kavita, SMB and a reading position
     * that survives a file being renamed, and told nobody about any of it. What went in was
     * not all of that: four lines, in the shape Apple's own What's New uses, because a
     * reader who opens a reading app is there to read. The rest of the history is in the
     * repository for anyone who wants it.
     */
    val releases: List<WhatsNewRelease> = listOf(
        WhatsNewRelease(
            version = "0.1.0",
            notes = listOf(
                WhatsNewNote(
                    icon = Icons.AutoMirrored.Filled.LibraryBooks,
                    title = R.string.whats_new_0_1_0_sources_title,
                    body = R.string.whats_new_0_1_0_sources_body,
                ),
                WhatsNewNote(
                    icon = Icons.Filled.FormatSize,
                    title = R.string.whats_new_0_1_0_reading_title,
                    body = R.string.whats_new_0_1_0_reading_body,
                ),
                WhatsNewNote(
                    icon = Icons.Filled.Bookmark,
                    title = R.string.whats_new_0_1_0_place_title,
                    body = R.string.whats_new_0_1_0_place_body,
                ),
                WhatsNewNote(
                    icon = Icons.Filled.Shield,
                    title = R.string.whats_new_0_1_0_private_title,
                    body = R.string.whats_new_0_1_0_private_body,
                ),
            ),
        ),
    )

    /**
     * What to show on this launch, recording the version either way.
     *
     * **The recording is unconditional and it happens here**, before anything is drawn.
     * Three of the spec's scenarios turn on that single line:
     *
     * - a first ever launch shows nothing "and the version is recorded as seen, so the next
     *   update is the first thing they are told about";
     * - a version with nothing worth saying shows nothing and "is still recorded as seen, so
     *   the entry is not shown late alongside the next one";
     * - and the sheet is *shown* rather than *dismissed* when the flag is written, because
     *   "a reader who swipes it away has still seen it". Nothing here waits for an action, so
     *   there is no way to be shown the screen and not be recorded as having been.
     *
     * Called once, from `AppShell`. About reads [releases] directly and never comes here.
     */
    fun onLaunch(
        installed: String,
        store: WhatsNewStore,
        releases: List<WhatsNewRelease> = this.releases,
    ): WhatsNewRelease? {
        val seen = store.seenVersion()
        store.record(installed)
        return release(installed = installed, seen = seen, releases = releases)
    }

    /**
     * The decision on its own, with nothing to write and nothing to read.
     *
     * `seen == null` is a first ever launch: no version has been recorded, so the app has
     * never been opened, so there is nothing to catch up on.
     */
    internal fun release(
        installed: String,
        seen: String?,
        releases: List<WhatsNewRelease>,
    ): WhatsNewRelease? {
        if (seen == null || seen == installed) return null
        return releases.firstOrNull { it.version == installed }
    }

    /**
     * Whether one version string is newer than another.
     *
     * Dot-separated numbers compared as numbers, so `0.10.0` sorts above `0.9.0` where a
     * string comparison would put it below. Anything non-numeric counts as zero: the log is
     * written here rather than parsed from anywhere, so a version this cannot read is a typo
     * rather than input, and the test that pins the order is what catches it.
     */
    internal fun isNewer(left: String, right: String): Boolean {
        val mine = left.split(".").map { it.toIntOrNull() ?: 0 }
        val theirs = right.split(".").map { it.toIntOrNull() ?: 0 }
        for (index in 0 until maxOf(mine.size, theirs.size)) {
            val one = mine.getOrElse(index) { 0 }
            val other = theirs.getOrElse(index) { 0 }
            if (one != other) return one > other
        }
        return false
    }
}

/** One version's worth of notes. */
data class WhatsNewRelease(val version: String, val notes: List<WhatsNewNote>)

/**
 * One line of a release note: an icon, a heading, and a sentence.
 *
 * Keyed by its heading's resource id where the row list needs an identity — two notes under
 * one heading would be one row drawn and one silently gone, which the test suite pins rather
 * than trusting.
 */
data class WhatsNewNote(
    val icon: ImageVector,
    @param:StringRes val title: Int,
    @param:StringRes val body: Int,
)

/**
 * The one version the reader has already been told about.
 *
 * A single string in `SharedPreferences`, beside the other small launch-time values, for the
 * reason `LibraryPreferences` gives: opening the progress database before the first screen to
 * learn whether to show a sheet would be a strange trade. iOS's `WhatsNewStore` keeps the
 * same string in `UserDefaults`.
 */
class WhatsNewStore(private val preferences: SharedPreferences) {

    companion object {
        fun open(context: Context): WhatsNewStore =
            WhatsNewStore(
                context.getSharedPreferences("app.storyarc.whatsnew", Context.MODE_PRIVATE),
            )

        private const val SEEN = "seen"
    }

    /** The version last recorded, or `null` on a device that has never opened the app. */
    fun seenVersion(): String? = preferences.getString(SEEN, null)

    fun record(version: String) {
        preferences.edit().putString(SEEN, version).apply()
    }
}
