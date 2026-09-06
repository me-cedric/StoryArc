package app.storyarc.feature.library

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * The place that holds what opens with no network has one name, and it is a place.
 *
 * The owner's decision for `one-vocabulary-in-four-languages` task 4.3: the destination is
 * named by its **location** — *on this device* — and the **promise** — *can be read without a
 * connection* — moves to the empty state, which is the one surface with room to read it.
 * Before the decision Android named a capability where iOS named a place, and iOS named a
 * transfer where Android named a place. Either name alone is defensible; two names for one
 * place is the defect.
 *
 * **This reads the catalogues as files** rather than resolving them through Robolectric,
 * because it asserts a claim about four languages at once and a compose rule holds one locale.
 * It reads `feature/settings`' catalogue as well as this module's, because the count and the
 * empty state are one vocabulary drawn on two screens, and a guard that watched one of them
 * would pass on the day the other moved.
 *
 * iOS asserts the same two claims over its own catalogues in `OfflineDestinationNameTests`.
 */
class OfflineDestinationNameTest {

    /**
     * Settings' own row states a figure, and the figure is downloads.
     *
     * **This row deliberately does not name the device, and that is not an oversight.** The
     * destination is named by its location; this figure is not the destination. It weighs the
     * app's own downloads and imports, and not a folder the reader added, which is readable
     * offline and counted nowhere here. A sweep on 2026-09-04 photographed "Nothing on this
     * device" over a device holding nine publications and moved these two strings to name the
     * transfer instead. Naming the place here would put that back.
     */
    @Test
    fun `both halves of the count name the transfer, in every language`() {
        for (key in listOf("settings_downloads_none", "settings_downloads_summary")) {
            for ((language, word) in TRANSFER) {
                val sentence = valueOf(key, SETTINGS, language)
                assertTrue(
                    "$language states $key as “$sentence”, which does not name the transfer.",
                    sentence.lowercase().contains(word),
                )
            }
            for ((language, place) in LOCATION) {
                val sentence = valueOf(key, SETTINGS, language)
                assertTrue(
                    "$language states $key as “$sentence”, which names a place the figure does not count.",
                    !sentence.lowercase().contains(place),
                )
            }
        }
    }

    @Test
    fun `the count carries one placeholder in every language`() {
        for ((language, _) in LOCATION) {
            val sentence = valueOf("settings_downloads_summary", SETTINGS, language)
            assertTrue(
                "$language states the count as “$sentence”, which is not one figure.",
                sentence.split("%1\$s").size == 2,
            )
        }
    }

    @Test
    fun `the empty state names the location and promises reading with no connection`() {
        for ((language, place) in LOCATION) {
            val sentence = valueOf("library_empty_on_device", LIBRARY, language)
            assertTrue(
                "$language states the empty shelf as “$sentence”, which does not name the location.",
                sentence.lowercase().contains(place),
            )
            assertTrue(
                "$language states the empty shelf as “$sentence”, which drops the promise.",
                sentence.lowercase().contains(PROMISE.getValue(language)),
            )
        }
    }

    /** One key's value in one language, read out of the catalogue that holds it. */
    private fun valueOf(key: String, module: String, language: String): String {
        val folder = if (language == "en") "values" else "values-$language"
        val file = File(moduleDirectory, "../$module/src/main/res/$folder/strings.xml")
        assertTrue("${file.path} is not there — has the catalogue moved?", file.isFile)
        val found = Regex("""<string name="$key"[^>]*>(.*?)</string>""", RegexOption.DOT_MATCHES_ALL)
            .find(file.readText())
        assertTrue("$key is not in $module's $folder catalogue.", found != null)
        return checkNotNull(found).groupValues[1].replace("\\'", "'")
    }

    private companion object {
        /** Set by this module's `build.gradle.kts`, from its own `projectDir`. */
        val moduleDirectory: String = System.getProperty("storyarc.library.projectDir")
            ?: error("storyarc.library.projectDir is unset — the test cannot find the catalogues.")

        const val LIBRARY = "library"
        const val SETTINGS = "settings"

        /** How each language says the destination's location. */
        val LOCATION = mapOf(
            "en" to "on this device",
            "fr" to "sur cet appareil",
            "de" to "auf diesem gerät",
            "es" to "en este dispositivo",
        )

        /** The word each language uses for the act of fetching a file. */
        val TRANSFER = mapOf(
            "en" to "download",
            "fr" to "téléchargé",
            "de" to "heruntergeladen",
            "es" to "descarga",
        )

        /** How each language says the promise the empty state carries. */
        val PROMISE = mapOf(
            "en" to "without a connection",
            "fr" to "sans connexion",
            "de" to "ohne verbindung",
            "es" to "sin conexión",
        )
    }
}
