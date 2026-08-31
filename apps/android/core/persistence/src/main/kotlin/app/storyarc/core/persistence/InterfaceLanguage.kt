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
    return createConfigurationContext(localeOverride(locale))
}

/**
 * A configuration carrying the chosen language **and nothing else**.
 *
 * `createConfigurationContext` takes an *override*, and `Configuration.updateFrom` applies
 * every field the override has populated. So handing it a copy of the current configuration
 * -- which is what this did until 2026-08-31 -- pins `uiMode`, `orientation`, `screenLayout`,
 * `densityDpi` and `screenWidthDp` at the moment the activity was attached. Both activities
 * declare those as configuration changes they handle themselves, so neither is recreated and
 * `attachBaseContext` never runs again: the frozen snapshot is the one the activity keeps.
 * The reader would have gone on drawing a light scheme after the device went dark, and the
 * comic reader pairs pages from `LocalConfiguration.orientation`, which would have stopped
 * changing on a rotation. Only for a reader who had chosen a language, which is why it went
 * unseen.
 *
 * A delta rather than a copy, then, which is what `AppCompatDelegateImpl.generateConfigDelta`
 * does and for this reason. **`fontScale` is the one field a fresh `Configuration` does not
 * leave unset**: `setToDefaults()` writes 1, and `updateFrom` applies any `fontScale` above
 * zero -- so an override built by construction alone would silently hold the whole activity
 * at the default text size, which is a far worse defect than the one being fixed. Zero is the
 * value `updateFrom` skips. Every other field defaults to an explicit "undefined" that it
 * already skips.
 *
 * `setLocale` also sets the layout direction, which is wanted: a right-to-left language is
 * not only a set of strings.
 */
private fun localeOverride(locale: Locale): Configuration = Configuration().apply {
    fontScale = 0f
    setLocale(locale)
}

/** The language the reader last chose, read early enough to build an activity with it. */
fun Context.chosenLanguage(): String? = SettingsStore.open(this).settings().language

/**
 * The locale a stored tag means, or null to leave the system's alone.
 *
 * Pure, so the one decision in [speaking] can be asserted without a device.
 *
 * The guard is the *answer*, not the input. `Locale.forLanguageTag` never refuses: it
 * answers the root locale for `""` and for anything it cannot parse, and a root-locale
 * interface is not something any reader ever asked for. Checking the result rather than the
 * string catches both, and needs no opinion about which strings are well formed. Null, blank
 * and unparseable all mean "the reader has not chosen", which is the state a fresh install
 * is in.
 */
internal fun interfaceLocale(tag: String?): Locale? =
    tag?.let { Locale.forLanguageTag(it) }?.takeIf { it != Locale.ROOT }
