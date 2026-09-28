package app.storyarc.feature.reader

import android.graphics.Bitmap
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * The model's half of [PagePlaceholder]: a plain ratio for every page it has actually
 * decoded, and nothing for the rest. iOS's `ReaderModelTests`
 * (`decodedRatiosMatchTheDecodedPages`) asserts the same table.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ReaderViewModelPagePlaceholderTest {

    private fun model() = ReaderViewModel(
        publication = Publication(
            identity = PublicationIdentity(normalizedPath = "/comics/one.cbz"),
            format = PublicationFormat.CBZ,
            displayTitle = "One",
            origin = MetadataOrigin.INFERRED,
        ),
        resolver = RuntimeEnvironment.getApplication().contentResolver,
        path = "/comics/one.cbz",
    )

    @Test
    fun `every decoded page reports its own width-over-height ratio`() {
        val model = model()
        model.decoded[0] = Bitmap.createBitmap(200, 300, Bitmap.Config.ARGB_8888)

        assertEquals(200f / 300f, model.decodedRatios()[0]!!, 0.001f)
        assertNull(model.decodedRatios()[4])
    }

    @Test
    fun `nothing decoded yet reports no ratio at all`() {
        assertEquals(emptyMap<Int, Float>(), model().decodedRatios())
    }
}
