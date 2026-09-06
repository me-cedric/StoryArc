package app.storyarc.feature.library

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.model.AppSettings
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.persistence.LibraryCache
import app.storyarc.core.persistence.SettingsStore
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File

/**
 * The filter menu files its values where the reader's language files them.
 *
 * The shelf, the search results and a reading list all collate in the reader's language. The
 * menu that narrows them did not: it sorted with a bare `sorted()`, which is Kotlin's
 * `compareTo` on `String` and therefore UTF-16 unit order. Every accented value landed after
 * every unaccented one, so a French reader looking for *Éditions du Lombard* found it after
 * *Zenith Press* — past the end of the alphabet, in a list the reader reads as an alphabet.
 *
 * Code point order is not the wrong collation. It is no collation at all, which is why the
 * defect is the same in all four languages StoryArc ships rather than only in some.
 *
 * iOS's `LibraryFacetsCollateTests` holds the same two names and the same expectation
 * (ADR-0001).
 *
 * Robolectric, because [LibraryViewModel] takes an `Application` and the chosen language is
 * read from `SharedPreferences` — the same reason [LibrarySortSpeaksTheReadersLanguageTest]
 * runs under it.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class LibraryFacetsCollateTest {

    private val application: Application get() = ApplicationProvider.getApplicationContext()

    /** The reader's choice, written where the app reads it back. */
    private fun choose(language: String?) {
        SettingsStore.open(application).save(AppSettings(language = language))
    }

    private fun publication(
        publisher: String,
        genre: String,
        tag: String,
        language: String,
    ) = Publication(
        identity = PublicationIdentity(normalizedPath = "/fixtures/$publisher.cbz"),
        format = PublicationFormat.CBZ,
        displayTitle = publisher,
        publisher = publisher,
        language = language,
        genres = listOf(genre),
        tags = listOf(tag),
        origin = MetadataOrigin.INFERRED,
    )

    private fun model(library: List<Publication>): LibraryViewModel {
        LibraryCache(File(application.cacheDir, "library.json")).write(
            LibraryCache.Snapshot(refreshedAtEpochMillis = 0L, publications = library),
        )
        return LibraryViewModel(application = application).apply { restoreCachedLibrary() }
    }

    /**
     * Two values whose order the alphabet and the code point table disagree about.
     *
     * *É* is U+00C9 and *Z* is U+005A, so every code point comparison puts *Zenith* first. No
     * language StoryArc ships agrees: all four file *É* with *E*.
     */
    private val accented = "Éditions du Lombard"
    private val plain = "Zenith Press"

    private val library = listOf(
        publication(publisher = accented, genre = "Épouvante", tag = "épisodique", language = "fr"),
        publication(publisher = plain, genre = "Zombies", tag = "zines", language = "zu"),
    )

    @Test
    fun `a French reader finds Editions before Zenith`() {
        choose("fr")
        assertEquals(
            "the publisher filter filed an accent past the end of the alphabet",
            listOf(accented, plain),
            model(library).availablePublishers(),
        )
    }

    @Test
    fun `genres and tags collate too, because they are read the same way`() {
        choose("fr")
        val viewModel = model(library)
        assertEquals(
            "the genre filter filed an accent past the end of the alphabet",
            listOf("Épouvante", "Zombies"),
            viewModel.availableGenres(),
        )
        assertEquals(
            "the tag filter filed an accent past the end of the alphabet",
            listOf("épisodique", "zines"),
            viewModel.availableTags(),
        )
    }

    /**
     * Language codes are ASCII by definition, so this case cannot go red on an accent.
     *
     * It is here because nothing validates what a `ComicInfo.xml` writes into `<LanguageISO>`:
     * a mis-tagged file carrying *Français* rather than *fr* reaches this list as it is
     * spelled. The list is collated for that reason, not for the codes.
     */
    @Test
    fun `the language filter is collated on whatever the files actually spell`() {
        choose("fr")
        assertEquals(
            "the language filter is not ordered",
            listOf("fr", "zu"),
            model(library).availableLanguages(),
        )
    }

    /**
     * The order is the reader's, so a reader who changes language changes the menu.
     *
     * Swedish files *Ö* after *Z*, which is the opposite of what French does with the same
     * letter — so one library gives two orders and neither is the code point one.
     */
    @Test
    fun `a reader who chose Swedish gets the Swedish order, not the French one`() {
        val swedish = listOf(
            publication(publisher = "Ödmjuk", genre = "g", tag = "t", language = "sv"),
            publication(publisher = plain, genre = "z", tag = "z", language = "zu"),
        )

        choose("sv")
        assertEquals(
            "Swedish files Ö after Z, and the menu did not",
            listOf(plain, "Ödmjuk"),
            model(swedish).availablePublishers(),
        )

        choose("fr")
        assertEquals(
            "French folds Ö onto O, and the menu did not",
            listOf("Ödmjuk", plain),
            model(swedish).availablePublishers(),
        )
    }

    /**
     * Two values that collate equal still come back in one fixed order.
     *
     * The collation is case-insensitive, matching the shelf's, so *marvel* and *Marvel* are the
     * same value to it. They are different values to `distinct()`, and a menu that draws them
     * either way round on two launches of one library looks broken.
     */
    @Test
    fun `values that collate equal keep one order`() {
        choose("fr")
        val both = listOf(
            publication(publisher = "marvel", genre = "g", tag = "t", language = "fr"),
            publication(publisher = "Marvel", genre = "z", tag = "z", language = "zu"),
        )
        assertEquals(
            "the menu has no fixed order",
            listOf("Marvel", "marvel"),
            model(both).availablePublishers(),
        )
    }
}
