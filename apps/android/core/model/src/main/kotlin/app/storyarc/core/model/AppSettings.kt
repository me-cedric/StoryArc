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
    val linkReadingThemeToAppearance: Boolean = false,
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
     * `native-experience`: the scheme "derives from the user's wallpaper by default, with a
     * setting to use the StoryArc palette instead". On by default, which is the half that
     * was already true -- the opt-out is the half that was not, and until it existed the
     * only way back to the brand palette was to choose OLED Dark, which is a different
     * setting meaning a different thing.
     *
     * Read only where [appearance] is not OLED Dark. True black and a wallpaper-derived
     * wash are incompatible asks and the explicit choice wins; `StoryArcTheme` decides
     * that, once, so no call site has to remember it.
     *
     * Android-only in effect. iOS has no dynamic colour to opt out of, so there is
     * deliberately no counterpart in `AppSettings.swift`.
     */
    val useDynamicColor: Boolean = true,
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
