package app.storyarc

import android.content.Context
import android.content.res.Configuration
import app.storyarc.core.persistence.SettingsStore
import java.util.Locale

/**
 * Runs the interface in the language the reader chose rather than the system's.
 *
 * `localization` requires an override that "switches immediately without a restart". The
 * override is applied to the activity's own context, before anything is created, and the
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
 */
internal fun Context.speaking(tag: String?): Context {
    if (tag == null) return this
    val configuration = Configuration(resources.configuration)
    configuration.setLocale(Locale.forLanguageTag(tag))
    return createConfigurationContext(configuration)
}

/** The language the reader last chose, read early enough to build the activity with it. */
internal fun Context.chosenLanguage(): String? = SettingsStore.open(this).settings().language
