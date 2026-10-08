package app.storyarc.feature.epubreader

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.os.Build
import android.view.View
import android.view.ViewGroup
import androidx.annotation.RequiresApi
import androidx.core.graphics.createBitmap
import app.storyarc.core.model.CurlTurn
import app.storyarc.core.model.PageCurl
import app.storyarc.core.model.PageTransition
import app.storyarc.core.model.ScrollAxis
import app.storyarc.core.model.TransitionChoices
import kotlin.coroutines.resume
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.shared.ExperimentalReadiumApi

// The curl over reflowable text, which is task 4.3b of `reader-theming-and-page-transitions`.
//
// `ReflowableTurn.kt` took the turn over from Readium and spent it on no raster at all: the
// dip is opaque at the moment the pager moves, so Fast fade never needed a picture. This does.
// The shader is the comic reader's, unchanged -- `PageCurl` and `PageRoll` both live in
// `:core:model` so that neither reader owns them -- so a reader who turns a page of prose and
// a reader who turns a page of a comic watch the same sheet roll.
//
// **What is rolled is a picture, and only while the turn runs.** `ebook-reader` keeps a
// reflowable page as live web content: text is selectable, links are followable, and a
// read-aloud voice walks the DOM. None of that survives a texture, so the texture exists for
// the length of one turn and the live page is underneath it the whole time.

/**
 * This view as it is drawn, at the display's own scale.
 *
 * A view's own width and height are already pixels, so a bitmap of that size is the page at
 * one texture pixel per display pixel -- which `page-transitions` asks for by name, and which
 * body text is the one content where the difference is unmistakable.
 *
 * ponytail: `draw(Canvas)` rather than `PixelCopy`. `PixelCopy` reads the window, and by the
 * time the incoming page is photographed the sheet is already over it -- so the window holds
 * the picture this is trying to take. Drawing one view draws that view. The ceiling is that a
 * hardware-only layer inside the web view can come back blank; every caller here reads a null
 * or an unusable raster as "no curl this time", which costs a transition and never a turn.
 */
internal fun View.raster(): Bitmap? {
    if (width <= 0 || height <= 0) return null
    val bitmap = createBitmap(width, height)
    draw(Canvas(bitmap))
    return bitmap
}

/**
 * The rolling sheet, drawn over the book while a turn runs.
 *
 * A plain [View] rather than a Compose island: this goes into the same `FrameLayout` the Fast
 * fade dip goes into, at the same index, and a `ComposeView` raised and torn down per turn
 * would cost a composition for one rectangle filled with a shader. The finger and the spring
 * live in [ProseCurlDriver]; this draws where they put the page.
 *
 * The shader is parsed once, in the constructor, for the reason `CurledPages` parses it once:
 * `RuntimeShader(source)` compiles the whole AGSL program, which is cheap once and wasteful on
 * every frame of every turn.
 */
@RequiresApi(Build.VERSION_CODES.TIRAMISU)
internal class CurlSheet(context: Context, private val page: Bitmap) : View(context), ProseSheet {

    private val shader = PageCurl.newShader()
    private val paint = Paint()

    /** The page arriving, once it has been rastered. Until then the page lies flat. */
    override var other: Bitmap? = null
        set(value) {
            field = value
            invalidate()
        }

    var isRightToLeft: Boolean = false

    /** Signed, as the comic reader's is: 0 to 1 for a forward turn, 0 to -1 for a turn back. */
    override var progress: Float = 0f
        set(value) {
            field = value
            invalidate()
        }

    override val turnWidth: Float get() = page.width.toFloat()

    init {
        // The sheet is a picture of the page. A reader touching it would be touching a
        // photograph, and the live page is one frame away underneath.
        isClickable = false
        isFocusable = false
    }

    override fun remove() {
        (parent as? ViewGroup)?.removeView(this)
    }

    override fun onDraw(canvas: Canvas) {
        val sheets = proseSheets(progress, page, other)
        PageCurl.update(
            shader,
            width = width.toFloat(),
            height = height.toFloat(),
            progress = sheets.progress,
            isRightToLeft = isRightToLeft,
            page = sheets.turning ?: page,
            beneath = sheets.under,
        )
        paint.shader = shader
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), paint)
    }
}

/**
 * Which raster turns, which lies under it, and at what forward progress.
 *
 * The comic reader's own choice, [CurlTurn.sheets], with the arriving page as both
 * neighbours: a turn back rolls the arriving page in over the leaving one. With no arriving
 * page yet the leaving page lies flat and whole, which is what is under the sheet, so the sheet
 * cannot show a page that is not there. iOS's `ReflowableCurl.sheets` is the twin.
 */
internal fun <T> proseSheets(progress: Float, page: T, other: T?): CurlTurn.Sheets<T> =
    CurlTurn.sheets(if (other == null) 0f else progress, page, other, other)

/**
 * The navigator's page, as the prose curl uses it: raised under a sheet, moved, rastered.
 *
 * @param host what the sheet is added to, above the book and below the chrome.
 * @param index where in [host] the sheet goes, which is where the dip goes.
 * @param navigator the book. Its own view is what is rastered: the sheet is in [host] by the
 *   time the arriving page is photographed, and a raster of [host] would photograph the sheet.
 */
@RequiresApi(Build.VERSION_CODES.TIRAMISU)
internal class NavigatorProsePage(
    private val host: ViewGroup,
    private val index: Int,
    private val navigator: EpubNavigatorFragment,
) : ProsePage {

    /** The page [raise] photographed, which [ahead] lays the neighbour over. */
    private var leaving: Bitmap? = null

    override fun raise(isRightToLeft: Boolean): ProseSheet? {
        val book = navigator.view ?: return null
        val outgoing = book.raster() ?: return null
        leaving = outgoing
        val sheet = CurlSheet(host.context, outgoing).apply {
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
            this.isRightToLeft = isRightToLeft
        }
        host.addView(sheet, index)
        return sheet
    }

    override fun ahead(forward: Boolean, isRightToLeft: Boolean): Bitmap? {
        val book = navigator.view as? ViewGroup ?: return null
        val outgoing = leaving ?: return null
        return ProseAhead.raster(book, ProseAhead.step(forward, isRightToLeft), outgoing)
    }

    @OptIn(ExperimentalReadiumApi::class)
    override suspend fun move(forward: Boolean): Boolean {
        val book = navigator.view as? ViewGroup
        val before = book?.let(ProseAhead::place)
        return movedTo(
            navigator.currentLocator,
            pageShifted = { book != null && ProseAhead.place(book) != before },
        ) {
            if (forward) navigator.goForward(animated = false) else navigator.goBackward(animated = false)
        }
    }

    /**
     * Two frames after the move: one for the moved page to lay out, one for it to draw. A
     * raster taken sooner photographs the page the reader is leaving.
     */
    override suspend fun arrived(): Bitmap? {
        val book = navigator.view ?: return null
        book.nextFrame()
        book.nextFrame()
        return book.raster()
    }

    private suspend fun View.nextFrame() =
        suspendCancellableCoroutine { continuation -> postOnAnimation { continuation.resume(Unit) } }
}

/**
 * The transition this reader draws itself, or null where Readium keeps the turn.
 *
 * `effective`, not the chosen mode: under Reduce Motion a chosen Slide runs as Fast fade, and
 * the turn has to follow that. Two modes answer now -- Fast fade, whose dip needs no picture
 * at all, and Curl, which needs two. iOS's `EpubReaderModel.drawnTurn` is the twin.
 */
internal val TransitionChoices.drawnTurn: PageTransition?
    get() = when (effective) {
        PageTransition.FAST_FADE -> PageTransition.FAST_FADE
        PageTransition.PAGE_CURL -> PageTransition.PAGE_CURL
        else -> null
    }

/**
 * Which page-turn rows to offer, and which of them this content cannot run.
 *
 * Beside the turns it decides rather than on the view model, which is at the line cap
 * `scripts/line-cap.mjs` holds. That is the better place for it anyway: this file already
 * holds [drawnTurn], which reads nothing else, and a reader of either has to read both.
 *
 * [reduceMotion] is a parameter rather than read here, so a recomposition on the reader's
 * `reduceMotionFlow` recomputes this too.
 */
internal fun EpubReaderViewModel.transitions(reduceMotion: Boolean): TransitionChoices =
    TransitionChoices(
        chosen = transition.value,
        // Reflowing text scrolls the way it is read; the axis is not a choice here.
        axis = ScrollAxis.VERTICAL,
        reduceMotion = reduceMotion,
        canCurl = canCurl,
        // The activity takes the turn over from Readium for both: `TurnInterceptor` steals
        // the drag, `FadeTurn` draws the dip, and `ProseCurlDriver` lets the finger roll a
        // raster of the page off a raster of the next one (task 8.12). Either was false until its
        // turn existed, because offering a mode that quietly gave a Slide instead would have
        // been worse than saying it was not available yet.
        canFade = true,
        canCurlOverText = true,
        isReflowable = true,
    )

/**
 * Calls [move], then waits until the page has turned. False when it never does within
 * [timeoutMillis].
 *
 * Readium's `goForward` answers before the page has moved -- it posts the scroll to a
 * coroutine and a JavaScript call -- and it answers true at the last page too, where nothing
 * moves at all. Its answer says nothing about whether a page turned. Two things do: the
 * location changes when the page does, and only then; and the view shifts, which it does
 * before Readium has reported where it landed. On the storyarc-ci emulator the report took 130
 * to 185 ms and the shift under a frame, so [pageShifted] ends the wait first, and the
 * location is what answers where the shift is not one (a turn that changes nothing the view
 * can see). So the curl rasters the incoming page only after this, and does not roll at all
 * where the book stood still.
 *
 * @param pageShifted polled between frames; true once the view has moved since [move] began.
 */
internal suspend fun <T> movedTo(
    location: Flow<T>,
    timeoutMillis: Long = MOVE_TIMEOUT_MILLIS,
    pageShifted: () -> Boolean = { false },
    move: () -> Unit,
): Boolean {
    val before = location.first()
    move()
    return withTimeoutOrNull(timeoutMillis) {
        coroutineScope {
            val moved = CompletableDeferred<Unit>()
            val watching = listOf(
                launch {
                    location.first { it != before }
                    moved.complete(Unit)
                },
                launch {
                    while (!pageShifted()) delay(SHIFT_POLL_MILLIS)
                    moved.complete(Unit)
                },
            )
            moved.await()
            watching.forEach { it.cancel() }
        }
    } != null
}

/** How often the view is asked whether the page has shifted. Under one frame at 60 Hz. */
internal const val SHIFT_POLL_MILLIS = 8L

/** How long a turn may take to report a new location before it counts as no turn. */
internal const val MOVE_TIMEOUT_MILLIS = 500L
