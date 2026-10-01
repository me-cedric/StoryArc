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
 * `ebook-reader`, *Fixed-layout EPUB*: background colour "remain[s] available" from the
 * reader itself. D34 is what notices the comic reader could set one nowhere but Settings.
 * iOS's `ReaderModelTests` (`chooseMatteRoundTrips`) asserts the same table.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ReaderViewModelMatteTest {

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
    fun `a chosen matte comes back to a fresh model, for the same series`() {
        val preferences = ReaderPreferences.open(RuntimeEnvironment.getApplication())
        model(preferences).chooseMatte("#E8EFE6")

        val second = model(preferences)
        assertEquals(
            "A matte chosen in the reader did not reach a fresh model for the same series.",
            "#E8EFE6",
            second.matte,
        )
    }

    @Test
    fun `clearing the matte removes it for a fresh model too`() {
        val preferences = ReaderPreferences.open(RuntimeEnvironment.getApplication())
        val first = model(preferences)
        first.chooseMatte("#E8EFE6")
        first.chooseMatte(null)

        assertNull("Clearing the matte left a colour behind.", model(preferences).matte)
    }
}
