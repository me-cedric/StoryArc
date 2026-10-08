package app.storyarc

import android.content.Context
import android.graphics.Bitmap
import androidx.glance.appwidget.testing.unit.hasStartActivityClickAction
import androidx.glance.appwidget.testing.unit.isLinearProgressIndicator
import androidx.glance.appwidget.testing.unit.runGlanceAppWidgetUnitTest
import androidx.glance.testing.unit.hasContentDescriptionEqualTo
import androidx.glance.testing.unit.hasTextEqualTo
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.QuickActionRequest
import app.storyarc.core.model.ReadingSnapshot
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * The home-screen widget's face, composed from a snapshot the way the system composes it.
 *
 * `native-experience` names widgets among the system affordances. ADR-0011: the widget reads
 * the [ReadingSnapshot] and nothing else, so each case hands it one and reads what it drew.
 * The snapshot's own rules are `ReadingSnapshotTest`'s, in `:core:model`.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ReadingWidgetTest {

    private val context = ApplicationProvider.getApplicationContext<Context>()

    private fun snapshot(fraction: Double?) = ReadingSnapshot.of(
        Publication(
            identity = PublicationIdentity(normalizedPath = "/library/Bone 1.cbz"),
            format = PublicationFormat.CBZ,
            displayTitle = "Bone 1",
            series = "Bone",
            origin = MetadataOrigin.INFERRED,
        ),
        fraction,
    )!!

    private val cover = Bitmap.createBitmap(32, 48, Bitmap.Config.ARGB_8888)

    @Test
    fun `with no book the widget says so, and a tap opens the library`() = runGlanceAppWidgetUnitTest {
        setContext(context)
        setAppWidgetSize(ReadingWidget.WIDE)
        provideComposable { ReadingWidgetContent(null, null) }

        onNode(hasTextEqualTo(context.getString(R.string.widget_empty))).assertExists()
        assertEquals(
            QuickActionRequest.Library,
            HomeScreenActions.requestFrom(ReadingWidgets.openIntent(context, null)),
        )
    }

    @Test
    fun `a wide widget names the book, its series and the part read`() = runGlanceAppWidgetUnitTest {
        setContext(context)
        setAppWidgetSize(ReadingWidget.WIDE)
        provideComposable { ReadingWidgetContent(snapshot(0.42), cover) }

        onNode(hasTextEqualTo("Bone 1")).assertExists()
        onNode(hasTextEqualTo("Bone")).assertExists()
        onNode(hasTextEqualTo(context.getString(R.string.widget_percent_read, 42))).assertExists()
        onNode(isLinearProgressIndicator(0.42f)).assertExists()
        onNode(hasContentDescriptionEqualTo("Bone 1")).assertExists()
    }

    @Test
    fun `a narrow widget keeps the cover, the title and the bar, and leaves the series out`() =
        runGlanceAppWidgetUnitTest {
            setContext(context)
            setAppWidgetSize(ReadingWidget.NARROW)
            provideComposable { ReadingWidgetContent(snapshot(0.42), cover) }

            onNode(hasTextEqualTo("Bone 1")).assertExists()
            onNode(hasContentDescriptionEqualTo("Bone 1")).assertExists()
            onNode(isLinearProgressIndicator(0.42f)).assertExists()
            onNode(hasTextEqualTo("Bone")).assertDoesNotExist()
        }

    @Test
    fun `a book never opened shows no part read, and no cover shows no image`() = runGlanceAppWidgetUnitTest {
        setContext(context)
        setAppWidgetSize(ReadingWidget.WIDE)
        provideComposable { ReadingWidgetContent(snapshot(null), null) }

        onNode(hasTextEqualTo("Bone 1")).assertExists()
        onNode(isLinearProgressIndicator(0f)).assertDoesNotExist()
        onNode(hasContentDescriptionEqualTo("Bone 1")).assertDoesNotExist()
    }

    @Test
    fun `a stored cover is no longer than the widget needs, and a small one is kept`() {
        val screenWide = ReadingWidgets.widgetSized(Bitmap.createBitmap(1206, 1809, Bitmap.Config.ARGB_8888))
        assertEquals(ReadingSnapshot.COVER_PIXELS, screenWide.height)
        assertEquals(320, screenWide.width)
        assertSame(cover, ReadingWidgets.widgetSized(cover))
    }

    @Test
    fun `a tap opens the book the widget names, through the quick action's intent`() = runGlanceAppWidgetUnitTest {
        val bone = snapshot(0.42)
        val open = ReadingWidgets.openIntent(context, bone)
        setContext(context)
        setAppWidgetSize(ReadingWidget.WIDE)
        provideComposable { ReadingWidgetContent(bone, cover) }

        onNode(hasStartActivityClickAction(open)).assertExists()
        assertEquals(
            QuickActionRequest.ContinueReading(bone.publicationId),
            HomeScreenActions.requestFrom(open),
        )
    }
}
