package app.storyarc.core.model

import kotlinx.serialization.Serializable

/**
 * Everything Settings holds that is not per-shelf and not per-source.
 *
 * Deliberately small. `settings-and-about` names seven groups, and most of them own
 * nothing of their own: Sources belongs to the connectors, Downloads to
 * `offline-downloads`, Reading defaults to [ShelfMemory]'s per-scope defaults, and
 * Privacy has nothing to toggle at all — its whole point is that the app has no backend
 * to opt out of. What is left is this.
 *
 * One value type rather than four keys, for the reason [ShelfMemory] is one blob: a
 * screen that reads five settings to draw one row should read them together, and a reset
 * should be an assignment rather than four deletions.
 *
 * @property appearance light, dark, or whatever the device says. Defaults to the device.
 * @property language a BCP-47 tag, or null to follow the system. `localization` requires
 *   the app to follow the system language and to allow an override; null is the
 *   difference between "the reader has not chosen" and "the reader chose the language the
 *   system happens to be set to today".
 * @property turnPagesWithVolumeButtons whether the volume buttons turn pages. Off by
 *   default, and `page-transitions` is the reason it is a setting at all: volume keys
 *   that silently stop changing the volume are a defect rather than a feature.
 * @property turnPagesByTappingTheEdges whether a tap in the leading or trailing third of
 *   the page turns it. On by default -- see the property for why the two defaults differ.
 * @property linkReadingThemeToAppearance whether the reading theme follows the app's
 *   appearance. Off by default, because `settings-and-about` is explicit that the two are
 *   separate — "a dark app chrome with a paper-white page is a legitimate preference" —
 *   and this is the "single opt-in setting" the same requirement then allows.
 */
@Serializable
data class AppSettings(
    val appearance: AppearanceMode = AppearanceMode.SYSTEM,
    val language: String? = null,
    val turnPagesWithVolumeButtons: Boolean = false,
    /**
     * Whether tapping the side of a page turns it.
     *
     * `page-transitions`: each zone is a third of the width, and with this off "a tap
     * anywhere toggles the chrome, and no tap turns a page" -- every other trigger still
     * works. **On by default**, because tapping the side of the page is how most readers
     * turn one; the sibling above is off by default for the opposite reason, that volume
     * keys which stop changing the volume are a surprise.
     *
     * A setting at all because a tap on a page is not always a turn: a reader panning a
     * zoomed page, or using a stylus, is doing something else with the same gesture.
     */
    val turnPagesByTappingTheEdges: Boolean = true,
    val linkReadingThemeToAppearance: Boolean = false,
    /**
     * The reading theme [linkReadingThemeToAppearance] adopts for a light appearance.
     *
     * `ebook-reader` / *Theme follows appearance*: the reader switches "between the light
     * and dark reading themes the reader chose as their pair, not to an arbitrary default".
     * Defaults to Paper, which is what the link used before the pair was a setting.
     */
    val lightReadingTheme: ThemePreset = ThemePreset.PAPER,
    /**
     * The reading theme [linkReadingThemeToAppearance] adopts for a dark appearance.
     *
     * Defaults to Quiet, for the same reason [lightReadingTheme] defaults to Paper.
     */
    val darkReadingTheme: ThemePreset = ThemePreset.QUIET,
    /**
     * `offline-downloads`: downloads "pause and state that they are waiting for Wi-Fi" on
     * cellular, and resume when it returns. Off by default, because a reader who has not
     * asked for the restriction did not ask to be stopped either.
     */
    val downloadOverWifiOnly: Boolean = false,
    /**
     * The most disk downloads may take, in bytes, or null for no bound.
     *
     * `offline-downloads`: at the limit the app "stops downloading ... and offers to remove
     * finished publications to make room". A bound nobody set is not a bound.
     */
    val maximumDownloadBytes: Long? = null,
    /**
     * `offline-downloads`: with this on, finishing a publication removes its download,
     * "its progress is kept, and the removal is undoable for 10 seconds".
     */
    val removeDownloadsAfterFinishing: Boolean = false,
    /**
     * Whether the chrome takes its colours from the wallpaper.
     *
     * `native-experience`: the scheme "is the StoryArc palette by default, with a setting to
     * take the device's wallpaper colours instead". **Off by default**, so an Android reader
     * and an iOS reader meet the same accent on a build neither has configured: `brand.accent`
     * is one token and was reaching only one of the two platforms.
     *
     * Changing this default does not change an install that already holds an answer.
     * `SettingsStore` reads a stored record, and a stored `true` stays `true`; only a fresh
     * install and a reset read [Defaults]. That is deliberate -- a reader who chose the
     * wallpaper, or merely lived with it, should not have their app change colour on an
     * update -- and it is why a frame of this has to come from a fresh install.
     *
     * Read only where [appearance] is not OLED Dark. True black and a wallpaper-derived
     * wash are incompatible asks and the explicit choice wins; `StoryArcTheme` decides
     * that, once, so no call site has to remember it.
     *
     * Android-only in effect. iOS has no dynamic colour to opt out of, so there is
     * deliberately no counterpart in `AppSettings.swift`.
     */
    val useDynamicColor: Boolean = false,
    /**
     * Whether the app may ask an open catalogue for a cover it has no other way to find.
     *
     * False until a reader turns it on, and the default is the requirement rather than a
     * taste: `cover-art` says the app "SHALL NOT request a cover from any third party until
     * a reader turns the lookup on", and AGENTS.md non-negotiable 2 says data leaves the
     * device only to sources the user configured. [CoverLookupProvider] names the three that
     * would be asked. An older stored file lacks the field, and the default says what that
     * means: off, which is never consent.
     */
    val lookUpMissingCovers: Boolean = false,
) {
    companion object {
        /**
         * What a reset returns to.
         *
         * `settings-and-about` requires a reset to state that "sources, downloads, and
         * reading progress are not affected", and this type is why that statement is
         * true rather than merely promised: it holds none of them.
         */
        val Defaults = AppSettings()
    }
}
