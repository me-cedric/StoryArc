package app.storyarc.feature.reader

import android.provider.Settings
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
 * `reading-themes`, *Brightness is reader-local*, over the comic reader.
 *
 * The window attribute itself is [ReaderBrightnessEffect]'s, which needs a real `Window` an
 * instrumented test would supply; this is the half a JVM test can reach, the state the
 * effect reads and [AdjustmentsSheet] writes.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ReaderViewModelBrightnessTest {

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
    fun `nothing in force until the reader moves the slider`() {
        assertNull(model().brightness.value)
    }

    @Test
    fun `choosing a value puts it in force`() {
        val viewModel = model()

        viewModel.chooseBrightness(0.4f)

        assertEquals(0.4f, viewModel.brightness.value!!, 0f)
    }

    @Test
    fun `the slider starts at the device's own level, not at full brightness`() {
        val resolver = RuntimeEnvironment.getApplication().contentResolver
        Settings.System.putInt(resolver, Settings.System.SCREEN_BRIGHTNESS, 51)

        assertEquals(0.2f, brightnessInForce(chosen = null, resolver = resolver), 0.001f)
    }

    @Test
    fun `the slider shows the reader's own value once they choose one`() {
        val resolver = RuntimeEnvironment.getApplication().contentResolver
        Settings.System.putInt(resolver, Settings.System.SCREEN_BRIGHTNESS, 51)

        assertEquals(0.7f, brightnessInForce(chosen = 0.7f, resolver = resolver), 0f)
    }
}
