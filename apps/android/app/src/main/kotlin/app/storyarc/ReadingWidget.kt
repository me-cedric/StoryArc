package app.storyarc

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.LinearProgressIndicator
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.appWidgetBackground
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.updateAll
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.ContentScale
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxHeight
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import app.storyarc.core.model.QuickAction
import app.storyarc.core.model.ReadingSnapshot
import app.storyarc.core.model.ReadingSnapshotStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException

/**
 * The home-screen widget: the book being read, its cover and how far the reader got.
 *
 * `native-experience` names widgets among the system affordances the app uses. ADR-0011 sets
 * the one rule this follows: the widget reads the [ReadingSnapshot] the app wrote and nothing
 * else, because it draws while the app may not be running. iOS's `StoryArcWidget` is the
 * other platform's widget over its own snapshot.
 */
internal class ReadingWidget : GlanceAppWidget() {

    override val sizeMode = SizeMode.Responsive(setOf(NARROW, WIDE))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val store = ReadingWidgets.store(context)
        val snapshot = withContext(Dispatchers.IO) { store.read() }
        val cover = snapshot?.let { withContext(Dispatchers.IO) { store.cover(it)?.path?.let(BitmapFactory::decodeFile) } }
        provideContent { GlanceTheme { ReadingWidgetContent(snapshot, cover) } }
    }

    companion object {
        /** Two cells square: the cover above the title. */
        val NARROW = DpSize(110.dp, 110.dp)

        /** Three cells or more across: the cover beside the title, the series and the percent. */
        val WIDE = DpSize(220.dp, 110.dp)
    }
}

/** The system's entry point for [ReadingWidget]. Declared in the manifest. */
class ReadingWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = ReadingWidget()
}

/** Where the snapshot lives, and how the app writes it. */
internal object ReadingWidgets {

    fun store(context: Context) = ReadingSnapshotStore(File(context.filesDir, "widget"))

    /**
     * Stores the book to continue and redraws every widget, when that changed anything.
     *
     * [cover] runs on the main thread, because the library's cover cache is not
     * meant for another thread. The files are written on the IO dispatcher.
     *
     * A full disk costs the widget its update, never the app its screen, so a failed write
     * is logged and not thrown. `Log` rather than Timber: Timber arrives with Readium, and
     * this app plants no tree, so a Timber call would print nothing.
     */
    @SuppressLint("LogNotTimber")
    suspend fun publish(context: Context, snapshot: ReadingSnapshot?, cover: suspend () -> Bitmap?) {
        val changed = try {
            withContext(Dispatchers.IO) {
                store(context).write(snapshot) { withContext(Dispatchers.Main) { cover() }?.let(::jpeg) }
            }
        } catch (failure: IOException) {
            Log.w(TAG, "The widget snapshot was not written", failure)
            false
        } catch (failure: IllegalStateException) {
            Log.w(TAG, "The widget snapshot was not written", failure)
            false
        }
        if (changed) ReadingWidget().updateAll(context)
    }

    private const val TAG = "ReadingWidgets"

    /**
     * What a tap opens: the book, through the launcher menu's own intent, or the library.
     *
     * The same intent as the quick action, so [HomeScreenActions.requestFrom] reads both and
     * the app has one path back into a book.
     */
    fun openIntent(context: Context, snapshot: ReadingSnapshot?): Intent =
        if (snapshot != null) {
            HomeScreenActions.intent(context, QuickAction.CONTINUE_ID, snapshot.publicationId)
        } else {
            HomeScreenActions.intent(context, QuickAction.LIBRARY_ID, null)
        }

    private fun jpeg(bitmap: Bitmap): ByteArray = ByteArrayOutputStream().also {
        bitmap.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, it)
    }.toByteArray()

    private const val JPEG_QUALITY = 85
}

/** The widget's face. Separate from [ReadingWidget] so a test can compose it from a snapshot. */
@Composable
internal fun ReadingWidgetContent(snapshot: ReadingSnapshot?, cover: Bitmap?) {
    val context = LocalContext.current
    Box(
        modifier = GlanceModifier
            .fillMaxSize()
            .appWidgetBackground()
            .cornerRadius(16.dp)
            .background(GlanceTheme.colors.widgetBackground)
            .clickable(actionStartActivity(ReadingWidgets.openIntent(context, snapshot)))
            .padding(12.dp),
        contentAlignment = Alignment.Center,
    ) {
        when {
            snapshot == null -> Text(
                text = context.getString(R.string.widget_empty),
                style = TextStyle(color = GlanceTheme.colors.onSurfaceVariant, fontSize = 14.sp),
            )
            LocalSize.current.width >= ReadingWidget.WIDE.width -> Wide(snapshot, cover)
            else -> Narrow(snapshot, cover)
        }
    }
}

@Composable
private fun Narrow(snapshot: ReadingSnapshot, cover: Bitmap?) {
    Column(modifier = GlanceModifier.fillMaxSize()) {
        Cover(snapshot, cover, GlanceModifier.fillMaxWidth().defaultWeight())
        Spacer(GlanceModifier.height(6.dp))
        Title(snapshot, maxLines = 1)
        Progress(snapshot)
    }
}

@Composable
private fun Wide(snapshot: ReadingSnapshot, cover: Bitmap?) {
    Row(modifier = GlanceModifier.fillMaxSize()) {
        Cover(snapshot, cover, GlanceModifier.width(COVER_WIDTH).fillMaxHeight())
        Spacer(GlanceModifier.width(12.dp))
        Column(modifier = GlanceModifier.fillMaxHeight()) {
            Title(snapshot, maxLines = 2)
            snapshot.series?.let {
                Text(
                    text = it,
                    maxLines = 1,
                    style = TextStyle(color = GlanceTheme.colors.onSurfaceVariant, fontSize = 13.sp),
                )
            }
            Spacer(GlanceModifier.defaultWeight())
            snapshot.percentRead?.let {
                Text(
                    text = LocalContext.current.getString(R.string.widget_percent_read, it),
                    style = TextStyle(color = GlanceTheme.colors.onSurfaceVariant, fontSize = 13.sp),
                )
            }
            Progress(snapshot)
        }
    }
}

@Composable
private fun Cover(snapshot: ReadingSnapshot, cover: Bitmap?, modifier: GlanceModifier) {
    if (cover != null) {
        Image(
            provider = ImageProvider(cover),
            contentDescription = snapshot.title,
            contentScale = ContentScale.Crop,
            modifier = modifier.cornerRadius(8.dp),
        )
    } else {
        // No cover yet, or none at all: a quiet well in the cover's place, never a broken image.
        Box(modifier = modifier.cornerRadius(8.dp).background(GlanceTheme.colors.secondaryContainer)) {}
    }
}

@Composable
private fun Title(snapshot: ReadingSnapshot, maxLines: Int) {
    Text(
        text = snapshot.title,
        maxLines = maxLines,
        style = TextStyle(color = GlanceTheme.colors.onSurface, fontSize = 15.sp, fontWeight = FontWeight.Medium),
    )
}

@Composable
private fun Progress(snapshot: ReadingSnapshot) {
    val fraction = snapshot.fractionRead ?: return
    Spacer(GlanceModifier.height(6.dp))
    LinearProgressIndicator(
        progress = fraction,
        modifier = GlanceModifier.fillMaxWidth(),
        color = GlanceTheme.colors.primary,
        backgroundColor = GlanceTheme.colors.surfaceVariant,
    )
}

private val COVER_WIDTH = 64.dp
