package app.storyarc.core.snapshots

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Shader
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity

/**
 * Fixture data for the catalogue: no files, no network, and the same picture on every run.
 */
object Fixtures {
    private val hues = floatArrayOf(14f, 205f, 140f, 280f, 42f, 335f, 180f, 95f)

    /** A cover of a fixed shape and colour that [seed] picks, so two titles differ at a glance. */
    fun cover(seed: Int, width: Int = 400, height: Int = 600): Bitmap {
        val hue = hues[Math.floorMod(seed, hues.size)]
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.shader = LinearGradient(
            0f, 0f, width.toFloat(), height.toFloat(),
            Color.HSVToColor(floatArrayOf(hue, 0.55f, 0.85f)),
            Color.HSVToColor(floatArrayOf((hue + 40f) % 360f, 0.7f, 0.35f)),
            Shader.TileMode.CLAMP,
        )
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), paint)
        paint.shader = null
        paint.color = Color.argb(70, 255, 255, 255)
        canvas.drawCircle(width * 0.7f, height * 0.3f, width * 0.22f, paint)
        paint.color = Color.argb(60, 0, 0, 0)
        canvas.drawRect(0f, height * 0.72f, width.toFloat(), height.toFloat(), paint)
        return bitmap
    }

    /** A publication with only what the screens read. */
    fun publication(
        title: String,
        format: PublicationFormat = PublicationFormat.CBZ,
        authors: List<String> = emptyList(),
        series: String? = null,
        number: String? = null,
        pageCount: Int? = null,
        summary: String? = null,
        publisher: String? = null,
        year: Int? = null,
    ) = Publication(
        identity = PublicationIdentity(normalizedPath = "/library/$title.${format.name.lowercase()}"),
        format = format,
        displayTitle = title,
        origin = MetadataOrigin.EMBEDDED,
        authors = authors,
        series = series,
        number = number,
        pageCount = pageCount,
        summary = summary,
        publisher = publisher,
        year = year,
    )
}
