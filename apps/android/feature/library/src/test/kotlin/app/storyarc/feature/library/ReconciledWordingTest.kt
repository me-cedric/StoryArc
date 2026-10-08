package app.storyarc.feature.library

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Five states the two apps used to word differently, now worded the same in four languages
 * (`one-vocabulary-in-four-languages` 4.2, `close-the-audited-gaps` 15.11, D31).
 *
 * **Both platforms' catalogues are read as files**, as `OfflineDestinationNameTest` does: a
 * claim about four languages at once is not decidable from one locale. This test asserts the
 * Android catalogues hold the agreed words and, in the same pass, that iOS's `xcstrings` holds
 * them too, so an edit to one platform that the other does not follow fails here or in iOS's
 * `ReconciledWordingTests`.
 *
 * A placeholder is written `{n}` for a count and `{s}` for a string, so `%1$d`/`%1$s` and iOS's
 * `%lld`/`%@` compare as the one thing they are.
 */
class ReconciledWordingTest {

    private class Row(
        val android: String,
        val module: String,
        val ios: String,
        val catalogue: String,
        val words: Map<String, String>,
    )

    @Test
    fun `android holds the agreed words in every language`() {
        for (row in ROWS) {
            for ((language, expected) in row.words) {
                assertEquals("${row.android} in $language", expected, androidValue(row, language))
            }
        }
    }

    @Test
    fun `ios holds the same words in every language`() {
        for (row in ROWS) {
            for ((language, expected) in row.words) {
                assertEquals("${row.ios} in $language", expected, iosValue(row, language))
            }
        }
    }

    private fun neutral(text: String) = text
        .replace("%1\$d", "{n}").replace("%1\$s", "{s}")
        .replace("%lld", "{n}").replace("%@", "{s}")
        .replace("\\'", "'")

    private fun androidValue(row: Row, language: String): String {
        val folder = if (language == "en") "values" else "values-$language"
        val file = File(moduleDirectory, "../${row.module}/src/main/res/$folder/strings.xml")
        assertTrue("${file.path} is not there — has the catalogue moved?", file.isFile)
        val found = Regex("""<string name="${row.android}"[^>]*>(.*?)</string>""", RegexOption.DOT_MATCHES_ALL)
            .find(file.readText())
        assertTrue("${row.android} is not in ${row.module}'s $folder catalogue.", found != null)
        return neutral(checkNotNull(found).groupValues[1])
    }

    /**
     * One key's value in one language, from the `xcstrings` file that holds it.
     *
     * A reader of one `"<language>": { "stringUnit": { ... "value": "…" } }` run inside the
     * key's own block, which is how Xcode writes every entry here. A JSON parser is not on this
     * module's test classpath and a second thing to keep true is not worth one comparison.
     */
    private fun iosValue(row: Row, language: String): String {
        val file = File(
            moduleDirectory,
            "../../../ios/Packages/StoryArcKit/Sources/${row.catalogue}/Resources/Localizable.xcstrings",
        )
        assertTrue("${file.path} is not there — has the catalogue moved?", file.isFile)
        val text = file.readText()
        val start = text.indexOf("\n    \"${row.ios}\": {")
        assertTrue("${row.ios} is not in ${row.catalogue}'s catalogue.", start >= 0)
        val end = text.indexOf("\n    \"", start + 1).let { if (it < 0) text.length else it }
        val block = text.substring(start, end)
        val found = Regex(
            """"$language": \{\s*"stringUnit": \{\s*"state": "[^"]*",\s*"value": "((?:[^"\\]|\\.)*)"""",
        ).find(block)
        assertTrue("${row.ios} has no $language value.", found != null)
        return neutral(checkNotNull(found).groupValues[1])
    }

    private companion object {
        /** Set by this module's `build.gradle.kts`, from its own `projectDir`. */
        val moduleDirectory: String = System.getProperty("storyarc.library.projectDir")
            ?: error("storyarc.library.projectDir is unset — the test cannot find the catalogues.")

        val ROWS = listOf(
            Row(
                "library_cell_progress", "library", "library.cell.progress %lld", "LibraryFeature",
                mapOf("en" to "{n}%% read", "fr" to "{n}%% lu", "de" to "{n}%% gelesen", "es" to "{n}%% leído"),
            ),
            Row(
                "reader_cannot_open", "reader", "reader.cannotOpen", "ReaderFeature",
                mapOf(
                    "en" to "This title could not be opened.",
                    "fr" to "Ce titre n’a pas pu être ouvert.",
                    "de" to "Dieser Titel lässt sich nicht öffnen.",
                    "es" to "No se pudo abrir este título.",
                ),
            ),
            Row(
                "reader_matte", "reader", "reader.matte", "ReaderFeature",
                mapOf(
                    "en" to "Colour behind a comic page",
                    "fr" to "Couleur derrière une page de BD",
                    "de" to "Farbe hinter einer Comicseite",
                    "es" to "Color detrás de una página de cómic",
                ),
            ),
            Row(
                "sources_remove_title", "settings", "sources.remove.title %@", "SettingsFeature",
                mapOf(
                    "en" to "Remove {s}?", "fr" to "Retirer {s} ?", "de" to "{s} entfernen?",
                    "es" to "¿Quitar {s}?",
                ),
            ),
            Row(
                "sources_remove_downloads_title", "settings", "sources.removeDownloads.title %@",
                "SettingsFeature",
                mapOf(
                    "en" to "Remove downloads from {s}?",
                    "fr" to "Supprimer les téléchargements de {s} ?",
                    "de" to "Downloads von {s} entfernen?",
                    "es" to "¿Quitar las descargas de {s}?",
                ),
            ),
        )
    }
}
