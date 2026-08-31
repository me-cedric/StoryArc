package app.storyarc.feature.settings

/**
 * One setting inside a group, named so that search can point at it and the group can light
 * it up when a reader arrives.
 *
 * `settings-and-about`: a search result "navigates there and highlights it". The highlight
 * needs an identity the two halves agree on — the index says which setting matched, the
 * screen decides which row that is. A string resource would serve until someone rewords a
 * label; an entry cannot be reworded by accident, and `when` names every screen that has
 * to answer for a new one.
 *
 * Only rows that are one thing are here. "Acknowledgements" is a section of a dozen
 * licences and "Language" is the whole group, so both stay group matches — pointing at
 * them would be pointing at a screen, which arriving there already does.
 *
 * Mirrored case for case by iOS's `SettingsAnchor` bar one: `DYNAMIC_COLOUR` has no iOS
 * counterpart, because Material You is Android's and there is nothing there to opt out of.
 */
internal enum class SettingsAnchor {
    DYNAMIC_COLOUR,
    LINK_READING_THEME,
    VOLUME_BUTTONS,
    READING_DEFAULTS,
    DOWNLOADS_WIFI_ONLY,
    DOWNLOADS_REMOVE_AFTER_FINISHING,
    DOWNLOADS_LIMIT,
    CLEAR_CACHE,
    CLEAR_HISTORY,
    CLEAR_DOWNLOADS,
    DIAGNOSTIC,
    ;

    /**
     * Where the setting lives. Declared once, so the index cannot claim a setting is on a
     * screen that does not show it.
     */
    val group: SettingsGroup
        get() = when (this) {
            DYNAMIC_COLOUR, LINK_READING_THEME -> SettingsGroup.APPEARANCE
            VOLUME_BUTTONS, READING_DEFAULTS -> SettingsGroup.READING
            DOWNLOADS_WIFI_ONLY, DOWNLOADS_REMOVE_AFTER_FINISHING, DOWNLOADS_LIMIT ->
                SettingsGroup.DOWNLOADS
            CLEAR_CACHE, CLEAR_HISTORY, CLEAR_DOWNLOADS, DIAGNOSTIC -> SettingsGroup.PRIVACY
        }

    /**
     * What a search result calls it: the row's own label, so the match reads as the thing
     * the reader is about to see rather than as a synonym for it.
     */
    val titleRes: Int
        get() = when (this) {
            DYNAMIC_COLOUR -> R.string.appearance_dynamic_colour
            LINK_READING_THEME -> R.string.appearance_link_theme
            VOLUME_BUTTONS -> R.string.reading_volume_buttons
            READING_DEFAULTS -> R.string.reading_defaults
            DOWNLOADS_WIFI_ONLY -> R.string.downloads_wifi_only
            DOWNLOADS_REMOVE_AFTER_FINISHING -> R.string.downloads_remove_after
            DOWNLOADS_LIMIT -> R.string.downloads_limit
            CLEAR_CACHE -> R.string.privacy_clear_cache
            CLEAR_HISTORY -> R.string.privacy_clear_history
            CLEAR_DOWNLOADS -> R.string.privacy_clear_downloads
            DIAGNOSTIC -> R.string.privacy_diagnostic
        }
}
