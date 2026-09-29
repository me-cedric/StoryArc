package app.storyarc.feature.reader

import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.persistence.ReaderPreferences
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * The storage half of a continuous scroll's position: a model remembers a fraction, and
 * a fresh model for the same publication reads it back. iOS's `ReaderModelTests`
 * (`scrollFractionRoundTrips`) asserts the same table.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ReaderViewModelScrollOffsetTest {

    private fun model(preferences: ReaderPreferences?) = ReaderViewModel(
        publication = Publication(
            identity = PublicationIdentity(normalizedPath = "/comics/one.cbz"),
            format = PublicationFormat.CBZ,
            displayTitle = "One",
            origin = MetadataOrigin.INFERRED,
        ),
        resolver = RuntimeEnvironment.getApplication().contentResolver,
        path = "/comics/one.cbz",
        shelfStore = preferences,
    )

    @Test
    fun `a saved scroll fraction comes back to a fresh model, for the page it was on`() {
        val preferences = ReaderPreferences.open(RuntimeEnvironment.getApplication())
        val first = model(preferences)
        assertNull(first.takeScrollRestore(page = 0))

        first.saveScrollFraction(0.6f, page = 2)

        val second = model(preferences)
        assertEquals(0.6f, second.takeScrollRestore(page = 2)!!, 0f)
        assertNull("A restore is handed over once.", second.takeScrollRestore(page = 2))
    }

    @Test
    fun `a fraction saved on one page is not restored onto another`() {
        // A position synced from another device, or a page turned to in another mode,
        // opens on a page the stored fraction was never through.
        val preferences = ReaderPreferences.open(RuntimeEnvironment.getApplication())
        model(preferences).saveScrollFraction(0.6f, page = 2)

        assertNull(model(preferences).takeScrollRestore(page = 5))
    }

    @Test
    fun `this session's first save does not erase what the last session left`() {
        // The scroll saves on its first layout, at the top of the page, before its
        // restore has run. That save used to overwrite the fraction it was about to read.
        val preferences = ReaderPreferences.open(RuntimeEnvironment.getApplication())
        model(preferences).saveScrollFraction(0.6f, page = 2)

        val reopened = model(preferences)
        reopened.saveScrollFraction(0f, page = 2)
        assertEquals(0.6f, reopened.takeScrollRestore(page = 2)!!, 0f)
    }

    @Test
    fun `with no preferences store, nothing is remembered and nothing throws`() {
        val model = model(preferences = null)

        model.saveScrollFraction(0.5f, page = 0)

        assertNull(model.takeScrollRestore(page = 0))
    }
}
