package app.storyarc.feature.library

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Every refusal a scan can report has a sentence in all four languages.
 *
 * `localization`'s *Supported languages* and *A refusal speaks the reader's language*: a
 * reader whose library refuses a file is the reader who most needs to understand, and until
 * this change those sentences were English literals in `core/format` — a module with no
 * `strings.xml`, where a translation gap cannot fail lint.
 *
 * **The four files are read as files.** `lint`'s `MissingTranslation` says the same thing at
 * build time, and this says it in the suite that owns the wording, with the missing name in
 * the failure. The two are not the same guard: lint reports a name English defines and a
 * locale does not, and this reports a refusal the scan can report and no locale words.
 *
 * `SkipReasonWordsTest` beside this one asserts that every case reaches one of these names.
 * This test asserts the names are answerable; that one asserts they are asked for.
 */
class SkipReasonCatalogueTest {

    @Test
    fun `every reason is worded in every language`() {
        for (locale in LOCALES) {
            val defined = namesIn(locale)
            for (name in NAMES) {
                assertTrue(
                    "values$locale/strings.xml does not word $name",
                    defined.containsKey(name),
                )
                assertTrue(
                    "values$locale/strings.xml words $name as nothing",
                    defined.getValue(name).isNotBlank(),
                )
            }
        }
    }

    /**
     * The one refusal whose two platforms disagreed, and how it was settled.
     *
     * iOS said *it is protected by its store's content protection*; this platform names the
     * kind of thing. `localization`'s *One sentence, assembled differently* settles it: "where
     * the sentences genuinely differ in what they tell the reader — one naming a place the
     * other leaves unnamed — the more informative one is the agreed wording". This wording
     * wins, and `LibraryFeature/Resources/Localizable.xcstrings` holds the same English.
     */
    @Test
    fun `the content-protection sentence is this platform's wording, on both platforms`() {
        assertEquals(
            "this audiobook is protected by its store’s content protection",
            namesIn("").getValue("library_skipped_reason_content_protected"),
        )
    }

    private fun namesIn(locale: String): Map<String, String> {
        val module = requireNotNull(System.getProperty(MODULE_DIRECTORY)) {
            "$MODULE_DIRECTORY is not set — see this module's build.gradle.kts"
        }
        val file = File(module, "src/main/res/values$locale/strings.xml")
        assertTrue("values$locale/strings.xml is not at ${file.absolutePath}", file.isFile)
        // A reader of one `<string name="…">…</string>` line, which is how every one of these
        // files is written. A parser would be a second thing to keep true.
        return STRING.findAll(file.readText())
            .associate { it.groupValues[1] to it.groupValues[2].trim() }
    }

    private companion object {
        /** Set by this module's `build.gradle.kts`, from its own `projectDir`. */
        const val MODULE_DIRECTORY = "storyarc.library.projectDir"

        /** The four `localization` names, as this platform's resource qualifiers. */
        val LOCALES = listOf("", "-fr", "-de", "-es")

        val STRING = Regex("""<string name="([^"]+)"[^>]*>(.*?)</string>""", RegexOption.DOT_MATCHES_ALL)

        /**
         * The names the library has to word, one per refusal the scan can report.
         *
         * Written out rather than derived from `SkipReason`, deliberately: a derived list would
         * pass on a case whose name was a typo, because both sides would carry the same typo.
         *
         * Seven, where iOS words eight. `PublicationIndexer` indexes a PDF without opening it
         * on this platform — `PdfRenderer` is a framework class and the indexer stays off the
         * device — so `pdfUnopenable` is a refusal this platform cannot reach, and a name for
         * it would be an unused resource rather than a mirrored one.
         */
        val NAMES = listOf(
            "library_skipped_reason_unsupported",
            "library_skipped_reason_not_there",
            "library_skipped_reason_format_not_recognised",
            "library_skipped_reason_archive_password_protected",
            "library_skipped_reason_archive_unreadable",
            "library_skipped_reason_content_protected",
            "library_skipped_reason_unknown",
        )
    }
}
