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
