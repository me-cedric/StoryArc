package app.storyarc.feature.library

import android.icu.text.ListFormatter
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalConfiguration

/**
 * A reader-facing list, joined the way the reader's own language joins one.
 *
 * `localization`: the app formats everything through platform locale services rather than
 * composing strings by hand. A hand-written `joinToString(", ")` gives French and German
 * readers an English list (no "and"/"et"/"und" before the last item, and the wrong
 * punctuation besides).
 *
 * `LocalConfiguration.current.locales[0]`, not `Locale.getDefault()`: the override
 * `settings-and-about` lets a reader set in place moves the composition's configuration, and
 * `Locale.getDefault()` would still answer the device's own language after that.
 */
@Composable
fun localizedList(items: List<String>): String =
    ListFormatter.getInstance(LocalConfiguration.current.locales[0]).format(items)
