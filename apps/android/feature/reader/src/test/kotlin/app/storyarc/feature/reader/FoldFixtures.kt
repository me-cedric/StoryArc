package app.storyarc.feature.reader

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import androidx.compose.material3.adaptive.HingeInfo
import androidx.compose.material3.adaptive.Posture
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.junit4.ComposeContentTestRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onRoot
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadingDirection
import app.storyarc.core.playback.SpokenAudio
import app.storyarc.core.snapshots.Fixtures
import java.io.File
import java.io.FileOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/** A comic and a posture for the foldable tests, written the way `Catalogue15ReaderChromeTest` writes its comic. */
internal object FoldFixtures {

    /** The Pixel Fold's open display, 2208 x 1840 px at 420 dpi. */
    const val INNER_QUALIFIERS = "w841dp-h701dp-xhdpi"

    /** The Pixel Fold's open display turned a quarter, the way it stands in tabletop posture. */
    const val TABLETOP_QUALIFIERS = "w701dp-h841dp-xhdpi"

    private fun page(seed: Int): Bitmap {
        val bitmap = Fixtures.cover(seed, 800, 1200)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE; textSize = 120f }
        Canvas(bitmap).drawText("Page ${seed + 1}", 220f, 640f, paint)
        return bitmap
    }

    /** A three page CBZ in [folder], opened as the reader opens any other. */
    fun model(
        folder: File,
        direction: ReadingDirection = ReadingDirection.LEFT_TO_RIGHT,
        speaker: SpokenAudio = SpokenAudio(),
    ): ReaderViewModel {
        val file = File(folder, "fold-comic.cbz")
        ZipOutputStream(FileOutputStream(file)).use { zip ->
            for (index in 0 until 3) {
                zip.putNextEntry(ZipEntry("page-%02d.png".format(index + 1)))
                page(index).compress(Bitmap.CompressFormat.PNG, 90, zip)
                zip.closeEntry()
            }
        }
        val publication = Fixtures.publication("Harbour Lights", PublicationFormat.CBZ, pageCount = 3)
            .copy(identity = PublicationIdentity(normalizedPath = file.path), readingDirection = direction)
        val context = ApplicationProvider.getApplicationContext<android.app.Application>()
        return ReaderViewModel(publication, context.contentResolver, file.path, speaker = speaker)
    }

    /** A fold that is half open, at [bounds] in window pixels. */
    fun halfOpen(bounds: Rect, isVertical: Boolean) =
        Posture(hingeList = listOf(HingeInfo(bounds, isFlat = false, isVertical, isSeparating = true, isOccluding = false)))
}

internal fun ComposeContentTestRule.bounds(description: String): Rect =
    onNodeWithContentDescription(description).fetchSemanticsNode().boundsInRoot

internal fun ComposeContentTestRule.shows(description: String) =
    onAllNodesWithContentDescription(description).fetchSemanticsNodes().isNotEmpty()

/** Waits for [model] to open and its first page to draw. */
internal fun ComposeContentTestRule.loaded(model: ReaderViewModel) {
    waitUntil(timeoutMillis = 10_000) { model.pages.value.isNotEmpty() }
    waitUntil(timeoutMillis = 10_000) { shows("Page 1 of 3") }
}

/** Every node on screen with a pane title. */
internal fun ComposeContentTestRule.panes(): List<SemanticsNode> =
    generateSequence(listOf(onRoot().fetchSemanticsNode())) { level -> level.flatMap { it.children }.ifEmpty { null } }
        .flatten()
        .filter { SemanticsProperties.PaneTitle in it.config }
        .toList()
