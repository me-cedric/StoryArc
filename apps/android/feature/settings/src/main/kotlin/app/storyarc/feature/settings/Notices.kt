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

    /** The licence text for an identifier, or null if the file is missing. */
    fun text(assets: AssetManager, licence: String): String? = runCatching {
        assets.open("licences/texts/$licence.txt").bufferedReader().use { it.readText() }
    }.getOrNull()
}
