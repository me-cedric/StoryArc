package app.storyarc.feature.library

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * 11.10: the search bar used to build its own `CertificatePins` from the store, once, the
 * first time it composed — not `dependencies.pins`, the set `CatalogueConnection` pins into
 * when a reader accepts a certificate. A certificate pinned anywhere after that first compose
 * was refused by remote search until the activity was recreated, because the bar's own copy
 * never saw it.
 *
 * Reads the module's own source rather than composing it, the way `ShelfRefreshTest` does for
 * the same reason: the defect was which `CertificatePins` instance reached `LibrarySearch.ask`,
 * and that is a wiring question a compose tree answers no better than the text of the call.
 */
class LibrarySearchPinsWiringTest {

    @Test
    fun `the search entry takes the app's pins as a parameter rather than building its own`() {
        val module = System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own source and will" +
                    " not go looking for it elsewhere — run it through Gradle" +
                    " (`pnpm gradle :feature:library:testDebugUnitTest`), which sets the" +
                    " property from the module directory.",
            )
        val file = File(module, BAR_SOURCE)
        assertTrue("$BAR_SOURCE is not under ${module.absolutePath} — has it moved?", file.isFile)

        val source = file.readText()
        assertFalse(
            "LibrarySearchEntry rebuilds its own CertificatePins again, so a certificate" +
                " pinned after it first composed is refused until the activity is recreated.",
            source.contains("CertificatePins(CertificatePinStore"),
        )
        assertTrue(
            "LibrarySearchEntry no longer takes a pins parameter.",
            source.contains("pins: CertificatePins,"),
        )
        assertTrue(
            "The question asked is no longer built from the parameter pins.",
            source.contains("search.ask(query.search, groups, registry, credentials, pins, searchScope)"),
        )
    }

    private companion object {
        /** Set by this module's `build.gradle.kts`, from its own `projectDir`. */
        const val MODULE_DIRECTORY = "storyarc.library.projectDir"
        const val BAR_SOURCE = "src/main/kotlin/app/storyarc/feature/library/LibrarySearchBar.kt"
    }
}
