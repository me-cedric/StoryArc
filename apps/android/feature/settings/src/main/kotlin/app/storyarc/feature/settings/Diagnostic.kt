package app.storyarc.feature.settings

import android.content.Context
import android.content.Intent
import android.os.Build
import app.storyarc.core.model.DiagnosticRedaction
import app.storyarc.core.model.ThemeScope
import app.storyarc.core.persistence.ReaderPreferences
import app.storyarc.core.persistence.SettingsStore
import app.storyarc.core.persistence.StorageUsage
import java.util.Locale

/**
 * The diagnostic export, assembled and redacted.
 *
 * `settings-and-about` asks for it to be "shown before sharing, with every credential,
 * token and server hostname redacted". Shown before sharing is the whole design: the
 * reader reads the text, then decides. Nothing is sent anywhere by the app.
 *
 * Assembled here rather than in a shared type. Every value is one the platform alone can
 * read, so a shared report builder would be a shape with no logic in it. What *is* shared
 * is the rule — [DiagnosticRedaction] — and it is shared because it is the part that
 * would be dangerous to get differently right on each platform.
 *
 * English, not localised. It goes into a bug report, and a report the maintainer cannot
 * read helps nobody. Every label is a fixed key rather than a sentence, for the same
 * reason.
 */
internal object Diagnostic {

    fun text(context: Context): String {
        val settings = SettingsStore.open(context).settings()
        val reader = ReaderPreferences.open(context)
        val memory = reader.themes()
        val usage = StorageUsage(context)
        val metrics = context.resources.configuration

        val lines = buildList {
            add("StoryArc diagnostic")
            add("")
            add("[App]")
            add("version = ${BuildInfo.version}")
            add("build = ${BuildInfo.build}")
            add("")
            add("[Device]")
            add("platform = Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})")
            // A class, not a model. `BuildInfo.deviceClass` settles it for both readers:
            // `Build.MODEL` narrows a person far more than "tablet" does, and
            // `settings-and-about` asked for the class. A diagnostic the reader shares
            // publicly is a stronger reason to hold that line, not a reason to relax it.
            add("deviceClass = ${BuildInfo.deviceClass(context)}")
            add("screenWidthDp = ${metrics.screenWidthDp}")
            add("locale = ${Locale.getDefault()}")
            add("fontScale = ${metrics.fontScale}")
            add("")
            add("[Settings]")
            add("appearance = ${settings.appearance}")
            add("language = ${settings.language ?: "system"}")
            add("volumeButtonsTurnPages = ${settings.turnPagesWithVolumeButtons}")
            add("readingThemeFollowsAppearance = ${settings.linkReadingThemeToAppearance}")
            add("")
            add("[Reading defaults]")
            for (scope in ThemeScope.entries) {
                val shelf = memory.default(scope)
                add("$scope.preset = ${shelf.theme.preset}")
                add("$scope.modified = ${shelf.theme.isModified}")
                add("$scope.transition = ${shelf.transition}")
                // Per scope rather than on its own line above: the fit is a per-series
                // choice now, and what a report can state is the default a shelf inherits.
                add("$scope.fit = ${shelf.fit}")
            }
            add("")
            add("[Storage]")
            add("cacheBytes = ${usage.cacheBytes()}")
            add("historyBytes = ${usage.historyBytes()}")
            add("")
            add("[Sources]")
            // Reported as a count rather than a list. A source's display name is text the
            // reader typed, which is exactly where a hostname would be — so the report
            // does not carry it at all, rather than carrying it redacted.
            add("configured = 0")
        }

        return DiagnosticRedaction.redact(lines.joinToString("\n"))
    }

    /**
     * Hands the text to whatever the reader picks.
     *
     * A share sheet rather than an upload. The app has no backend to send it to, which is
     * the claim the Privacy screen above it makes.
     */
    fun shareIntent(text: String): Intent = Intent.createChooser(
        Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_SUBJECT, "StoryArc diagnostic")
            putExtra(Intent.EXTRA_TEXT, text)
        },
        null,
    )
}
