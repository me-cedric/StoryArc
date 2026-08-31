package app.storyarc.feature.epubreader

import app.storyarc.core.model.AppSettings
import app.storyarc.core.model.AppearanceMode
import app.storyarc.core.model.ThemePreset
import app.storyarc.core.model.presetMatching

/**
 * Everything the reader takes out of Settings › Appearance, decided in one place.
 *
 * The reflowable reader is the app's one screen that is its own activity, so it is the one
 * screen that has to fetch these rather than inherit them from `MainActivity`'s
 * composition. Until this existed it fetched them in two places and got one of them wrong:
 * the chrome was built with a hardcoded `AppearanceMode.SYSTEM`, so a reader who chose
 * Light, Dark or OLED Dark saw their choice on every screen in the app except the one they
 * spend the evening on. `settings-and-about` requires an appearance to apply "immediately
 * across the whole app without a restart", and a book is not outside the app.
 *
 * The two answers are deliberately taken from *different values of the same choice*, which
 * is the part that is easy to get backwards:
 *
 *  - [chrome] is the reader's **literal** choice, `SYSTEM` included. `StoryArcTheme` asks
 *    the device itself when it is handed `SYSTEM`, and it asks from inside the composition
 *    — so handing over the literal choice is what keeps `settings-and-about`'s "the app
 *    follows when the device switches theme" true while a book is open. Resolving it first
 *    would freeze the reader in whatever the device happened to be showing at the moment
 *    the book was opened.
 *  - [linkedPreset] is the **resolved** appearance, because `presetMatching` has no answer
 *    for "follow the device" and says so. Null unless the reader opted in, which leaves the
 *    shelf's own theme in force.
 *
 * OLED Dark is why those are not one question. It reaches [chrome], where a true-black
 * chrome is the whole point of the setting, and it maps to Quiet rather than to anything
 * darker in [linkedPreset], because a reading surface is deliberately never pure black —
 * pure black smears during a page turn, which is the exact motion this app is built around.
 * `settings-and-about` puts both halves in one sentence — "the setting is honoured where it
 * helps and explained where it does not". This decides the honoured half only. The
 * explaining is the Appearance screen's: its OLED Dark row carries
 * `appearance_oled_dark_note`, which says the page itself stays just above black and why.
 */
internal data class ReaderAppearance(
    val chrome: AppearanceMode,
    val useDynamicColor: Boolean,
    val linkedPreset: ThemePreset?,
) {
    companion object {
        /**
         * @param settings what the reader chose, as the store gave it back.
         * @param device what `resolved()` made of [AppSettings.appearance]. Passed in rather
         *   than worked out here because resolving `SYSTEM` needs a `Configuration`, and a
         *   rule that needs no Android to decide should not need one to test.
         */
        fun of(settings: AppSettings, device: AppearanceMode): ReaderAppearance =
            ReaderAppearance(
                chrome = settings.appearance,
                useDynamicColor = settings.useDynamicColor,
                linkedPreset = if (settings.linkReadingThemeToAppearance) {
                    presetMatching(device)
                } else {
                    null
                },
            )
    }
}
