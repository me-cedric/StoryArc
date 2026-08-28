package app.storyarc

import android.content.Context
import android.content.res.Configuration
import android.view.ContextThemeWrapper
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import java.util.Locale

/**
 * Runs the interface in the language the reader chose rather than the system's.
 *
 * `localization` requires an override that "switches immediately without a restart", so the
 * choice is carried into the composition: every `stringResource` below this point resolves
 * against the overridden configuration, and nothing is recreated.
 *
 * Not `LocaleManager.applicationLocales`, although that is the platform's own per-app
 * language and would also reach strings resolved outside a composition. It exists only from
 * API 33, StoryArc supports 31, and setting it tears the activity down -- measured on an
 * emulator, where the app left the screen rather than redrawing in the new language. A
 * language chosen inside the app switches inside the app.
 */
@Composable
internal fun WithInterfaceLanguage(tag: String?, content: @Composable () -> Unit) {
    val context = LocalContext.current
    val configuration = LocalConfiguration.current
    if (tag == null) {
        content()
        return
    }
    val overridden = remember(tag, configuration) {
        Configuration(configuration).apply { setLocale(Locale.forLanguageTag(tag)) }
    }
    CompositionLocalProvider(
        LocalConfiguration provides overridden,
        LocalContext provides remember(context, overridden) { Localised(context, overridden) },
    ) {
        content()
    }
}

/**
 * The activity, with different resources.
 *
 * A [Context.createConfigurationContext] result would do for strings and lose everything
 * else: it is not the activity, and Compose finds the activity by walking the context chain.
 * A file picker asked for its result registry through that and found nothing. A
 * [ContextThemeWrapper] keeps the activity underneath and only overrides the configuration.
 */
private class Localised(base: Context, configuration: Configuration) : ContextThemeWrapper(base, 0) {
    init {
        applyOverrideConfiguration(configuration)
    }
}

