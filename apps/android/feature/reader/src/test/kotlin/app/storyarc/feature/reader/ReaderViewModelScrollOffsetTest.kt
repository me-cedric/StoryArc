package app.storyarc.feature.reader

import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.persistence.ReaderPreferences
import org.junit.Assert.assertEquals
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
    fun `a saved scroll fraction comes back to a fresh model for the same publication`() {
        val preferences = ReaderPreferences.open(RuntimeEnvironment.getApplication())
        val first = model(preferences)
        assertEquals(0f, first.restoredScrollFraction(), 0f)

        first.saveScrollFraction(0.6f)

        val second = model(preferences)
        assertEquals(0.6f, second.restoredScrollFraction(), 0f)
    }

    @Test
    fun `with no preferences store, nothing is remembered and nothing throws`() {
        val model = model(preferences = null)

        model.saveScrollFraction(0.5f)

        assertEquals(0f, model.restoredScrollFraction(), 0f)
    }
}
