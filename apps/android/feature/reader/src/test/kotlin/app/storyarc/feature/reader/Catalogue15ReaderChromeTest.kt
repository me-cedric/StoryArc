package app.storyarc.feature.reader

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.snapshots.CATALOGUE_QUALIFIERS
import app.storyarc.core.snapshots.Fixtures
import app.storyarc.core.snapshots.Look
import app.storyarc.core.snapshots.catalogue
import java.io.File
import java.io.FileOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Catalogue entry 15: the comic reader with its chrome up, on the first page of a three page
 * comic. The comic is a real archive written for the test, so the reader opens it as it opens
 * any other.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = CATALOGUE_QUALIFIERS)
class Catalogue15ReaderChromeTest {

    @get:Rule
    val compose = createComposeRule()

    @get:Rule
    val folder = TemporaryFolder()

    private fun page(seed: Int): Bitmap {
        val bitmap = Fixtures.cover(seed, 800, 1200)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE; textSize = 120f }
        Canvas(bitmap).drawText("Page ${seed + 1}", 220f, 640f, paint)
        return bitmap
    }

    private fun comic(): File {
        val file = folder.newFile("fixture-comic.cbz")
        ZipOutputStream(FileOutputStream(file)).use { zip ->
            for (index in 0 until 3) {
                zip.putNextEntry(ZipEntry("page-%02d.png".format(index + 1)))
                page(index).compress(Bitmap.CompressFormat.PNG, 90, zip)
                zip.closeEntry()
            }
        }
        return file
    }

    private fun draw(look: Look) {
        val file = comic()
        val publication = Fixtures.publication("Harbour Lights", PublicationFormat.CBZ, pageCount = 3)
            .copy(identity = app.storyarc.core.model.PublicationIdentity(normalizedPath = file.path))
        val context = ApplicationProvider.getApplicationContext<android.app.Application>()
        val model = ReaderViewModel(publication, context.contentResolver, file.path)
        compose.catalogue(
            "15-reader-chrome",
            look,
            act = {
                waitUntil(timeoutMillis = 10_000) { model.pages.value.isNotEmpty() }
                onRoot().performClick()
            },
        ) { ReaderScreen(viewModel = model, onClose = {}) }
    }

    @Test
    fun light() = draw(Look.Light)

    @Test
    fun dark() = draw(Look.Dark)
}
