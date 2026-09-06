package app.storyarc.feature.epubreader

import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalConfiguration
import app.storyarc.core.designsystem.theme.resolved
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

/**
 * The reading theme the device's own appearance dictates, re-read on every change.
 *
 * `ebook-reader` / *Theme follows appearance*: the switch happens "then and there rather than
 * at the next open". `LocalConfiguration` is what carries a night-mode change into a
 * composition whose activity `configChanges` kept alive, so this is where the answer is live
 * and a value read from `resources.configuration` is not. Null unless the reader linked the
 * two, which leaves the shelf's own theme in force.
 */
@Composable
internal fun linkedReadingTheme(settings: AppSettings): ThemePreset? =
    ReaderAppearance
        .of(settings, settings.appearance.resolved(LocalConfiguration.current))
        .linkedPreset

/**
 * Takes the appearance's reading theme, while the book stays open.
 *
 * The value used to reach the view model through its constructor alone, which the activity
 * read once, so a device that turned dark mid-chapter took the chrome with it and left the
 * page as it was until the book was closed and reopened.
 *
 * `null` means the reader never linked the two, and it does nothing — the shelf's own theme
 * stays in force. That is the scenario's second clause.
 *
 * It goes through [EpubReaderViewModel.adopt] rather than writing the theme itself, because
 * that is what moves the flow the activity's `LaunchedEffect(theme, values, transition)`
 * watches — and that effect captures the reading position, submits the preferences and goes
 * back to the position. `reading-themes` requires the position to survive a repagination.
 *
 * A change that names the theme already in force does nothing either. Dark and OLED Dark both
 * mean Quiet, so a reader moving between them would otherwise lose every axis they had moved,
 * for an appearance change the reading theme cannot see.
 *
 * An extension rather than a member, for both of the reasons iOS puts its own `follow` in
 * `LinkedPreset.swift`: this rule belongs beside the appearance it reads, and the two view
 * models are each at their language's line cap.
 */
internal fun EpubReaderViewModel.follow(linked: ThemePreset?) {
    if (linked == null || linked == theme.value.preset) return
    adopt(linked)
}
