package app.storyarc.core.persistence

import android.content.Context
import android.content.res.Configuration
import java.util.Locale

/**
 * Runs the interface in the language the reader chose rather than the system's.
 *
 * `localization` requires an override that "switches immediately without a restart". The
 * override is applied to an activity's own context, before anything is created, and the
 * activity is recreated when the choice changes: the app stays open and its state is
 * restored, which is what a reader means by no restart.
 *
 * Not through the composition alone. Carrying an overridden `Configuration` down as a
 * composition local reaches everything drawn inside the activity's window and nothing drawn
 * in another one -- a dropdown menu is a `Popup`, which is its own window with the activity's
 * own context, and every menu in the app stayed in the system language while the screen
 * behind it changed. Measured on an emulator.
 *
 * Not `LocaleManager.applicationLocales` either, although that is the platform's own per-app
 * language. It arrives in API 33 and StoryArc supports 31, and setting it tore the activity
 * down rather than recreating it: the app left the screen entirely. Also measured.
 *
 * **Here rather than in `:app`, because the app has two activities and both need it.** The
 * EPUB reader is its own activity in its own module -- Readium's navigator is a `Fragment`
 * and needs a `FragmentManager` -- and `:feature:epubreader` cannot depend on `:app`. While
 * this lived in `:app` the reader was the one screen the override never reached: 109 string
 * keys across 94 `stringResource` call sites stayed in the system language the moment a book
 * opened. This module already owns [SettingsStore], which is where the answer comes from, so
 * it is where both activities can reach it.
 */
fun Context.speaking(tag: String?): Context {
    val locale = interfaceLocale(tag) ?: return this
    val configuration = Configuration(resources.configuration)
    configuration.setLocale(locale)
    return createConfigurationContext(configuration)
}

/** The language the reader last chose, read early enough to build an activity with it. */
fun Context.chosenLanguage(): String? = SettingsStore.open(this).settings().language

/**
 * The locale a stored tag means, or null to leave the system's alone.
 *
 * Pure, so the one decision in [speaking] can be asserted without a device. Blank is null
 * rather than a tag: `Locale.forLanguageTag("")` answers the *root* locale rather than
 * refusing, and a root-locale interface is not something any reader ever asked for. Null
 * and blank both mean "the reader has not chosen", which is the state a fresh install is in.
 */
internal fun interfaceLocale(tag: String?): Locale? =
    tag?.takeIf { it.isNotBlank() }?.let { Locale.forLanguageTag(it) }
