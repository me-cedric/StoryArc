package app.storyarc.feature.settings

import android.content.res.AssetManager
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * One thing StoryArc ships that someone else wrote.
 *
 * Read from `packages/licences/notices.json`, staged into the app's assets. It is staged
 * rather than read from the repository because BSD and Apache require the notice to
 * travel with the *binary*: a notices file only a developer can see does not discharge
 * the obligation, and neither does a list typed into Kotlin that drifts from the audit.
 *
 * @property why not decoration. `settings-and-about` asks for every library to be listed;
 *   a dependency whose reason nobody can state is a dependency to remove, and the About
 *   screen is where that becomes visible.
 */
@Serializable
internal data class Notice(
    val name: String,
    val version: String? = null,
    val licence: String,
    /**
     * The component's own copyright line.
     *
     * Separate from the licence body because `texts/` holds the SPDX *template* for each
     * licence, and a template says `Copyright (c) <year> <owner>`. Shipping that
     * placeholder discharges nothing — BSD and Apache both require the real notice to
     * travel with the binary.
     */
    val copyright: String? = null,
    val url: String,
    val platforms: List<String> = emptyList(),
    val why: String,
)

@Serializable
private data class NoticeFile(
    @SerialName("notices") val notices: List<Notice> = emptyList(),
)

/**
 * Everything to acknowledge, for this platform.
 *
 * Filtered by platform, because half the inventory is the other app's: showing an Android
 * reader that the app depends on the Readium *Swift* toolkit would be worse than showing
 * nothing.
 */
internal object Notices {
    private val json = Json { ignoreUnknownKeys = true }

    fun forAndroid(assets: AssetManager): List<Notice> = runCatching {
        val text = assets.open("licences/notices.json").bufferedReader().use { it.readText() }
        json.decodeFromString<NoticeFile>(text).notices
            .filter { it.platforms.isEmpty() || it.platforms.contains("android") }
    }.getOrDefault(emptyList())

    /**
     * One component's licence, with its own copyright line in place of the template's.
     *
     * The SPDX text carries a placeholder on its first line. Substituting rather than
     * prepending, so the notice reads as the project's own licence rather than as a
     * licence with a note stapled to it.
     */
    fun text(assets: AssetManager, notice: Notice): String? = runCatching {
        assets.open("licences/texts/${notice.licence}.txt").bufferedReader().use { it.readText() }
    }.getOrNull()?.let { body -> withCopyright(body, notice.copyright) }

    /** Replaces an SPDX placeholder copyright line, or leaves the body alone. */
    internal fun withCopyright(body: String, copyright: String?): String {
        if (copyright.isNullOrBlank()) return body
        val lines = body.lines().toMutableList()
        val at = lines.indexOfFirst { PLACEHOLDER.containsMatchIn(it) }
        // No placeholder means the text already names its holder. Prepending a second
        // copyright line to such a text would state two, and one of them would be wrong.
        if (at < 0) return body
        lines[at] = copyright
        return lines.joinToString("\n")
    }

    private val PLACEHOLDER = Regex(
        """<year>|<owner>|\[yyyy]|\[name of copyright owner]""",
        RegexOption.IGNORE_CASE,
    )
}
