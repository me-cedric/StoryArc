package app.storyarc.feature.library

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.model.AppSettings
import app.storyarc.core.model.LibraryIndex
import app.storyarc.core.model.LibraryQuery
import app.storyarc.core.model.LibrarySort
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.persistence.LibraryCache
import app.storyarc.core.persistence.SettingsStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File
import java.util.Locale

/**
 * The library files a title where the reader's language files it, not where the device does.
 *
 * `localization` moves the interface into the language the reader chose. The override goes
 * through `createConfigurationContext` and reaches an activity's own context, so it reaches
 * every word drawn from resources — and it does not reach a view model. [LibraryViewModel]
 * called `LibraryIndex.arrange` with no locale, so the sort took `Locale.getDefault()`, which
 * is the *device's* language. A reader who set StoryArc to Spanish on a German phone got
 * German collation, and *ñ* filed where German files it.
 *
 * The three languages below disagree about exactly this, and the disagreement is the assertion:
 *
 * - Spanish makes *ñ* a letter of its own after *n*, so *Ñandú* follows *Nuez*.
 * - German folds *ä* and *å* onto *a*, so *Ñandú* precedes *Nuez* and both follow *Ähre*.
 * - Swedish puts *å* and *ä* after *z*, so *Ångström* and *Ähre* end the shelf.
 *
 * Measured rather than assumed: the same five titles under Foundation's collation produce the
 * same three orders, so iOS's `LibrarySortSpeaksTheReadersLanguageTests` holds this table too
 * and the two platforms cannot drift apart on it (ADR-0001).
 *
 * Robolectric, because [LibraryViewModel] takes an `Application` and the chosen language is
 * read from `SharedPreferences` — the same reason `RecentSearchMemoryTest` runs under it.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class LibrarySortSpeaksTheReadersLanguageTest {

    private val application: Application get() = ApplicationProvider.getApplicationContext()

    /**
     * Five titles whose order differs in each of the three languages.
     *
     * One author on all five, so the search case below reaches every row at the same rank and
     * the sort is what remains to decide their order.
     */
    private val library = listOf("Zorro", "Ähre", "Nuez", "Ñandú", "Ångström").map { title ->
        Publication(
            identity = PublicationIdentity(normalizedPath = "/fixtures/$title.cbz"),
            format = PublicationFormat.CBZ,
            displayTitle = title,
            authors = listOf("Nordqvist"),
            origin = MetadataOrigin.INFERRED,
        )
    }

    private val inSpanish = listOf("Ähre", "Ångström", "Nuez", "Ñandú", "Zorro")
    private val inGerman = listOf("Ähre", "Ångström", "Ñandú", "Nuez", "Zorro")
    private val inSwedish = listOf("Ñandú", "Nuez", "Zorro", "Ångström", "Ähre")

    /** The reader's choice, written where the app reads it back. */
    private fun choose(language: String?) {
        SettingsStore.open(application).save(AppSettings(language = language))
    }

    /**
     * A view model holding the library.
     *
     * Through the cache the app itself restores from, rather than a scan: it is the one route
     * that fills the shelf and rebuilds it without a folder tree behind it.
     */
    private fun model(): LibraryViewModel {
        LibraryCache(File(application.cacheDir, "library.json")).write(
            LibraryCache.Snapshot(refreshedAtEpochMillis = 0L, publications = library),
        )
        return LibraryViewModel(application = application).apply { restoreCachedLibrary() }
    }

    private fun shelf(language: String?): List<String> {
        choose(language)
        return model().visible.value.map { it.displayTitle }
    }

    // The shelf

    @Test
    fun `a reader who chose Spanish gets Spanish collation, with n-tilde after n`() {
        assertEquals("the shelf did not file ñ where Spanish files it", inSpanish, shelf("es"))
    }

    /**
     * **This case alone cannot catch the defect on an English host, and that is recorded rather
     * than hidden.** English and German file these five titles identically, so a shelf that
     * ignored the choice would pass here. The Spanish and Swedish cases are the ones that went
     * red before the fix; this one states German's answer so the table is complete and so the
     * case fails on a German host if the shelf ever stops asking.
     */
    @Test
    fun `a reader who chose German gets German collation, with a-umlaut folded onto a`() {
        assertEquals("the shelf did not file ä where German files it", inGerman, shelf("de"))
    }

    @Test
    fun `a reader who chose Swedish gets Swedish collation, with a-ring and a-umlaut after z`() {
        assertEquals("the shelf did not file å where Swedish files it", inSwedish, shelf("sv"))
    }

    @Test
    fun `the three languages disagree, so passing any one of them is a real answer`() {
        assertEquals(3, setOf(inSpanish, inGerman, inSwedish).size)
    }

    /**
     * One view model, two languages.
     *
     * The view model is what a language change keeps: `recreate()` retains the `ViewModelStore`,
     * so the shelf is re-sorted by the rebuild that follows rather than by a new model. In the
     * app that rebuild is `LibraryScreen`'s `ON_RESUME` effect calling `refreshProgress()`;
     * here it is a query nudged away and back, which is the same door and needs no store.
     */
    @Test
    fun `changing the language reorders the shelf`() {
        choose("de")
        val viewModel = model()
        val first = viewModel.visible.value.map { it.displayTitle }

        choose("es")
        viewModel.setQuery(viewModel.query.value.copy(ascending = false))
        viewModel.setQuery(viewModel.query.value.copy(ascending = true))
        val second = viewModel.visible.value.map { it.displayTitle }

        assertNotEquals("the shelf kept one order across two languages", first, second)
        assertEquals(inGerman, first)
        assertEquals(inSpanish, second)
    }

    // Search results, which share the screen

    @Test
    fun `search results are collated in the reader's language too`() {
        choose("es")
        val viewModel = model()
        viewModel.setQuery(viewModel.query.value.copy(search = "nordqvist"))
        val found = viewModel.matchGroups.value.flatMap { it.publications }.map { it.displayTitle }
        assertEquals("the search results ignored the chosen language", inSpanish, found)
    }

    // A reading list's contents, which are the same shelf under another heading

    @Test
    fun `a reading list sorted by title collates in the reader's language`() {
        val shown = ListOrdering.arrange(
            entries = library.map { it.id },
            order = ListOrder(sort = LibrarySort.TITLE),
            publications = library,
            locale = Locale.forLanguageTag("sv"),
        )
        val titles = shown.map { id -> library.first { it.id == id }.displayTitle }
        assertEquals("the reading list ignored the chosen language", inSwedish, titles)
    }

    /**
     * The one call site that draws a reading list, pinned as source.
     *
     * `ShelfDetailScreen` builds the order inside a composable, and a Robolectric composition
     * would prove the rows are drawn rather than which locale they were ordered by. The
     * behaviour above proves the rule; this proves the screen asks for it.
     */
    @Test
    fun `the reading list screen hands the sort the reader's locale`() {
        val module = System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own source and will" +
                    " not go looking for it elsewhere — run it through Gradle" +
                    " (`pnpm gradle :feature:library:testDebugUnitTest`), which sets the" +
                    " property from the module directory.",
            )
        val file = File(module, SHELF_DETAIL_SOURCE)
        if (!file.isFile) error("$SHELF_DETAIL_SOURCE is not under ${module.absolutePath}")
        assertTrue(
            "ShelfDetailScreen sorts in the device's language",
            file.readText().contains("locale = viewModel.readerLocale()"),
        )
    }

    // The default, which must stay the process locale

    @Test
    fun `a caller that names no locale still gets the process locale`() {
        choose("sv")
        val query = LibraryQuery()
        val byDefault = LibraryIndex.arrange(library, query).map { it.displayTitle }
        val byProcess =
            LibraryIndex.arrange(library, query, Locale.getDefault()).map { it.displayTitle }
        assertEquals(
            "the default locale followed the reader instead of the process",
            byProcess,
            byDefault,
        )
    }

    private companion object {
        /** Set by this module's `build.gradle.kts`, from its own `projectDir`. */
        const val MODULE_DIRECTORY = "storyarc.library.projectDir"
        const val SHELF_DETAIL_SOURCE =
            "src/main/kotlin/app/storyarc/feature/library/ShelfDetailScreen.kt"
    }
}
