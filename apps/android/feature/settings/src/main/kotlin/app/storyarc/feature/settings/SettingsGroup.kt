package app.storyarc.feature.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.selection.selectable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Book
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Palette
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import app.storyarc.core.model.AppSettings

/**
 * The seven groups `settings-and-about` names, in the order it names them.
 *
 * The order is the spec's and not alphabetical or arbitrary: Sources first because it is
 * what a new reader needs, About last because it is what nobody needs twice.
 */
enum class SettingsGroup {
    SOURCES,
    APPEARANCE,
    READING,
    DOWNLOADS,
    LANGUAGE,
    PRIVACY,
    ABOUT,
    ;

    companion object

    val titleRes: Int
        get() = when (this) {
            SOURCES -> R.string.settings_sources
            APPEARANCE -> R.string.settings_appearance
            READING -> R.string.settings_reading
            DOWNLOADS -> R.string.settings_downloads
            LANGUAGE -> R.string.settings_language
            PRIVACY -> R.string.settings_privacy
            ABOUT -> R.string.settings_about
        }

    /** What a group that cannot be entered yet says instead of opening onto nothing. */
    val pendingRes: Int
        get() = when (this) {
            SOURCES -> R.string.settings_sources_pending
            DOWNLOADS -> R.string.settings_downloads_pending
            else -> R.string.settings_pending
        }

    val icon: ImageVector
        get() = when (this) {
            SOURCES -> Icons.Filled.Folder
            APPEARANCE -> Icons.Filled.Palette
            READING -> Icons.Filled.Book
            DOWNLOADS -> Icons.Filled.Download
            LANGUAGE -> Icons.Filled.Language
            PRIVACY -> Icons.Filled.Lock
            ABOUT -> Icons.Filled.Info
        }

    /**
     * The group's current value, in one line.
     *
     * `settings-and-about`: each summary row "states its current value, so a setting can
     * be checked without entering the group". A group with nothing to state yet says
     * what it will hold — which is a value too, and a more honest one than silence.
     */
    @Composable
    fun summary(settings: AppSettings, library: LibrarySummary = LibrarySummary()): String = when (this) {
        APPEARANCE -> stringResource(settings.appearance.labelRes)
        READING -> stringResource(
            if (settings.turnPagesWithVolumeButtons) {
                R.string.settings_reading_summary_volume
            } else {
                R.string.settings_reading_summary
            },
        )
        LANGUAGE -> settings.language?.let { tag ->
            val locale = java.util.Locale.forLanguageTag(tag)
            locale.getDisplayLanguage(locale).replaceFirstChar { it.titlecase(locale) }
        } ?: stringResource(R.string.settings_language_system)
        PRIVACY -> stringResource(R.string.settings_privacy_summary)
        ABOUT -> stringResource(R.string.settings_about_summary)
        // Both of these are built now, so both state a value. A summary that still said
        // "not built yet" would be the one line on this screen a reader could check
        // against the group behind it and find wrong.
        SOURCES -> if (library.sources == 0) {
            stringResource(R.string.settings_sources_none)
        } else {
            pluralStringResource(R.plurals.settings_sources_summary, library.sources, library.sources)
        }
        DOWNLOADS -> if (library.bytesOnDisk == 0L) {
            stringResource(R.string.settings_downloads_none)
        } else {
            stringResource(
                R.string.settings_downloads_summary,
                android.text.format.Formatter.formatShortFileSize(
                    androidx.compose.ui.platform.LocalContext.current,
                    library.bytesOnDisk,
                ),
            )
        }
    }
}

/**
 * What the summary rows need to know about the library.
 *
 * A value rather than two more parameters, because both numbers come from the same place and
 * a screen that took them separately would be one refactor away from showing a source count
 * next to another library's size.
 */
data class LibrarySummary(val sources: Int = 0, val bytesOnDisk: Long = 0L)

/**
 * One row of a search result: a group, or a setting inside one.
 *
 * `settings-and-about` asks for matches to be listed "with their group path", which is
 * what `settingRes == null` distinguishes — a group match shows its current value, a
 * setting match shows the group it lives in.
 */
internal data class SettingMatch(val group: SettingsGroup, val settingRes: Int?)

/**
 * Every group, and the settings inside them, that a query matches.
 *
 * The searchable index is a list rather than a reflection over the screens, because the
 * screens are Compose functions and a list is the only thing that can be *read* without
 * running one. It is short enough to keep honest and long enough to be worth having: a
 * reader looking for "volume" should not have to guess it lives under Reading.
 *
 * Matched against the English keys rather than the localised strings. That is a known
 * limit and the honest one — matching translations needs a `Context` this function does
 * not have, and an index keyed on the current locale would miss a reader who searches in
 * the language they think in. ponytail: English keys; index the localised strings when a
 * reader complains.
 */
internal fun SettingsGroup.Companion.search(query: String): List<SettingMatch> {
    val needle = query.trim().lowercase()
    if (needle.isEmpty()) return SettingsGroup.entries.map { SettingMatch(it, null) }
    return SEARCHABLE.filter { (terms, _) -> terms.any { it.contains(needle) } }.map { it.second }
}

/**
 * What each row can be found by.
 *
 * Terms rather than one label, so "night" finds Appearance and "licence" finds About —
 * a reader searches for the thing they want, not for what the screen calls it.
 */
private val SEARCHABLE: List<Pair<List<String>, SettingMatch>> = listOf(
    listOf("sources", "folder", "share", "opds", "kavita", "server") to
        SettingMatch(SettingsGroup.SOURCES, null),
    listOf("appearance", "theme", "dark", "light", "night", "oled", "black", "colour", "color") to
        SettingMatch(SettingsGroup.APPEARANCE, null),
    listOf("reading", "page", "turn") to SettingMatch(SettingsGroup.READING, null),
    listOf("volume", "buttons", "keys", "page turn") to
        SettingMatch(SettingsGroup.READING, R.string.reading_volume_buttons),
    listOf("default", "defaults", "series", "preset") to
        SettingMatch(SettingsGroup.READING, R.string.reading_defaults),
    listOf("downloads", "offline") to SettingMatch(SettingsGroup.DOWNLOADS, null),
    listOf("language", "locale", "translation") to SettingMatch(SettingsGroup.LANGUAGE, null),
    // "cache", "storage" and "space" point here rather than at Downloads. Downloads is
    // still pending, and Privacy is where the sizes are shown and cleared today — a
    // search term that lands on an empty screen is worse than no search term.
    listOf("privacy", "analytics", "tracking", "account", "data", "cache", "storage", "space", "clear") to
        SettingMatch(SettingsGroup.PRIVACY, null),
    listOf("diagnostic", "diagnostics", "bug", "report", "log") to
        SettingMatch(SettingsGroup.PRIVACY, R.string.privacy_diagnostic),
    listOf("about", "version", "author", "licence", "license", "acknowledgements", "credits", "support") to
        SettingMatch(SettingsGroup.ABOUT, null),
)

/**
 * The smallest a row may be, whatever its text asks for.
 *
 * A one-line row measured 34dp on the emulator while a two-line row measured 48dp, so
 * the target a reader had to hit depended on how long the label happened to be. Material
 * and WCAG both put the floor at 48dp.
 */
private val minimumRowHeight = 48.dp

/**
 * A whole row that responds to a tap, announced as a button.
 *
 * `Modifier.clickable` alone leaves a screen reader to guess what the row is; the role
 * is what makes it announce as one thing rather than as a heading beside a subtitle.
 */
@Composable
internal fun Modifier.clickableRow(onClick: () -> Unit): Modifier =
    heightIn(min = minimumRowHeight).clickable(role = Role.Button, onClick = onClick)

/**
 * A whole row that picks one of a set, announced with its state.
 *
 * `mergeDescendants` is what makes it announce as one control rather than as a radio
 * button followed by two unrelated pieces of text.
 */
@Composable
internal fun Modifier.selectableRow(selected: Boolean, onClick: () -> Unit): Modifier =
    heightIn(min = minimumRowHeight)
        .selectable(selected = selected, role = Role.RadioButton, onClick = onClick)
        .semantics(mergeDescendants = true) {}
