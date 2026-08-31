package app.storyarc.feature.library

import android.graphics.Bitmap
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.ui.graphics.Color
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcColor
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.MatchGroup
import app.storyarc.core.model.MatchKind
import app.storyarc.core.model.Publication
import kotlin.math.roundToInt

/** The widest a cover is ever drawn at an ordinary font scale. See [coverMaximumWidth]. */
internal val COVER_MAXIMUM_WIDTH = 168.dp

/**
 * The font scale at which the reader has left the ordinary range.
 *
 * Android's own Font size slider stops at 1.3 outside accessibility settings, and the
 * larger steps (1.5, 1.8, 2.0) live behind them. iOS reads the same boundary as
 * `DynamicTypeSize.isAccessibilitySize`.
 */
private const val ACCESSIBILITY_FONT_SCALE = 1.3f

/**
 * How much wider a cover is drawn once the reader is at an accessibility font scale.
 *
 * A step, not a scale, and there are exactly two of them. Cover width and text size are not
 * the same quantity: multiplying the cell by the font would trade away the artwork — the
 * one thing this app says is the interface — to make room for words. What a cramped caption
 * actually needs is *one fewer column*, and a column is a step.
 *
 * 1.4 is chosen against the widths that bracket a phone. It takes a ~400 dp phone from
 * three columns to two — the caption goes from 112 dp, where `Harbour Lights #1` wraps and
 * its neighbours' series lines truncate, to 174 dp — and it leaves a 360 dp phone at the
 * two columns it already had rather than dropping it to one. `library-browsing` still wants
 * a grid at every text size; it is the truncation that has to go, not the shelf.
 *
 * iOS's `accessibilityCoverStep` is the same number for the same reason.
 */
private const val ACCESSIBILITY_COVER_STEP = 1.4f

/**
 * The narrowest a cover may be drawn, given the room the window has and how large the
 * reader has asked for text to be.
 *
 * `design.md` §4: "Minimum cover width scales by size class: 104 / 132 / 158 pt". One
 * number for every window is what left a 1400 dp tablet showing roughly eleven columns of
 * phone-sized covers — a shelf reads as a shelf at a size the room can afford, and a room
 * that got bigger should not simply hold more of the same postage stamps. Those three are
 * the answer at every ordinary font scale and are unchanged; [fontScale] only decides
 * whether the tier is taken as written or one step wider.
 *
 * The two width thresholds are Material's own medium (600 dp) and expanded (840 dp)
 * breakpoints, which is also where `StoryArcWindowClass` will grow its remaining cases.
 * Taken from the window's width rather than from a device check, for the reason
 * `WindowClass.kt` sets out at length: a multi-window slot, a rotation and a fold are all
 * the same event. The font scale is the second such event.
 */
internal fun coverMinimumWidth(windowWidthDp: Int, fontScale: Float = 1f): Dp {
    val tier = when {
        windowWidthDp >= 840 -> 158.dp
        windowWidthDp >= 600 -> 132.dp
        else -> 104.dp
    }
    return tier.steppedFor(fontScale)
}

/**
 * The widest a cover is ever drawn. Above it a phone shows one and a half of them.
 *
 * The cap steps with the minimum, or it would become the thing that decides the layout: a
 * tablet at an accessibility font scale asks for 221 dp columns, and a cap still pinned at
 * 168 dp would grant the wider columns and then draw 168 dp covers inside them, leaving a
 * ragged strip of empty shelf down the trailing edge. iOS derives its maximum from its
 * minimum and gets this for nothing.
 */
internal fun coverMaximumWidth(fontScale: Float = 1f): Dp =
    COVER_MAXIMUM_WIDTH.steppedFor(fontScale)

/**
 * How wide one shortcut in the continue-reading row is at an ordinary font scale.
 *
 * Slightly larger than a phone's shelf cover, because there are few of them and they are
 * what the reader came back for.
 */
private val CONTINUE_READING_WIDTH = 128.dp

/**
 * This width, one accessibility step wider when the reader is past [ACCESSIBILITY_FONT_SCALE].
 *
 * Rounded to whole dp, so both platforms land on the same 146 / 185 / 221.
 */
private fun Dp.steppedFor(fontScale: Float): Dp =
    if (fontScale >= ACCESSIBILITY_FONT_SCALE) {
        (value * ACCESSIBILITY_COVER_STEP).roundToInt().dp
    } else {
        this
    }

/**
 * The cover grid.
 *
 * `library-browsing`: "the number of grid columns follows the available width, and
 * cover size stays within the readable range defined in the design tokens".
 * [BoundedAdaptive] is what does that — a fixed column count would give a phone
 * postage stamps and a tablet a wall of enormous covers, and the platform's own
 * `GridCells.Adaptive` takes only the lower bound. [coverMinimumWidth] supplies the
 * lower bound the window can afford.
 *
 * iOS's `CoverGrid` uses the same two bounds for the same reason.
 *
 * The grid does **not** scroll itself back to the top when the continue-reading row
 * arrives. It used to, on the reasoning that a lazy grid anchors on its first visible item
 * and so would leave the new row off-screen. That is true, and it is still not worth
 * moving a reader who did not ask to be moved: they scrolled somewhere deliberately and
 * an asynchronous read of stored positions is no reason to take it back.
 */
@Composable
internal fun CoverGrid(
    publications: List<Publication>,
    viewModel: LibraryViewModel,
    /**
     * In-progress publications, most recently read first. Empty means the row is
     * not drawn — `library-browsing` requires it absent rather than shown empty.
     */
    continueReading: List<Publication> = emptyList(),
    /**
     * Search results under their own headings. Empty means there is no search running and
     * the shelf is drawn as one run of covers.
     */
    groups: List<MatchGroup> = emptyList(),
    /**
     * The shelf divided into headed runs, or empty when it is one uniform run.
     *
     * `library-browsing` asks a long library to be "divided by series where a publication
     * declares one, and otherwise by the active sort key, with headings that stay visible
     * while their section is on screen". [LibrarySections] decides *whether* and *how*; this
     * only draws the answer, and empty is a real answer rather than a missing one.
     *
     * Ignored while a search is running: the results are already grouped by why they
     * matched, and a second set of headings cutting across the first would be two answers to
     * one question. The caller settles that — see `LibraryScreen`.
     */
    sections: List<LibrarySection> = emptyList(),
    /**
     * What to do when a cover is tapped: show that publication's page.
     *
     * `publication-detail`: a page is reachable "from every surface that shows a
     * publication", and choosing a cover is how a reader reaches it. The grid does not know
     * what a page is any more than it knows what a reader is — a feature module never
     * depends on another feature module, so the app layer wires the two together.
     */
    onOpen: (Publication) -> Unit,
    /**
     * What to do when the reader takes the continue-reading row: open the book.
     *
     * The row is the one affordance on this screen that offers to *resume*, and
     * `publication-detail` keeps resuming and inspecting apart — "the book opens at the
     * recorded position, without this page in between". A reader who tapped Continue has
     * already chosen; putting a page in front of them would be asking the question twice.
     */
    onResume: (Publication) -> Unit = onOpen,
    /** A long press, where a publication is put on a shelf. Nil where there is nowhere to put it. */
    onAddToShelf: ((Publication) -> Unit)? = null,
    /**
     * What the reader has picked, or null when they are not picking.
     *
     * `collections-and-reading-lists` wants publications "selected in bulk from the
     * library", and the library is a grid or a list depending on a control the reader
     * already owns -- so both of them take this, and neither is the one that works.
     */
    selection: Set<String>? = null,
    onToggle: (Publication) -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val density = LocalDensity.current
    val windowWidth = LocalWindowInfo.current.containerSize.width
    // The reader's text size is the second input to the cover size, not only the window's
    // width: three columns of caption on a phone at an accessibility font scale is a
    // recognisable cover under an unreadable label, which inverts what a caption is for.
    val fontScale = density.fontScale
    val minimumWidth = remember(density, windowWidth, fontScale) {
        coverMinimumWidth(with(density) { windowWidth.toDp().value.toInt() }, fontScale)
    }
    val maximumWidth = remember(fontScale) { coverMaximumWidth(fontScale) }
    // Pixels, not dp: a cover decoded at dp size is blurry on every device made
    // since 2010.
    val maxPixelSize = remember(density, maximumWidth) { with(density) { maximumWidth.roundToPx() } }

    val gridState = rememberLazyGridState()

    LazyVerticalGrid(
        // Both bounds, not just the minimum: `GridCells.Adaptive` has no maximum, so a
        // narrow window stretched its single column to the full width and a cover filled
        // the screen. `BoundedAdaptive` is the other half of the scenario.
        columns = remember(minimumWidth, maximumWidth) {
            BoundedAdaptive(minimumWidth, maximumWidth)
        },
        state = gridState,
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(
            horizontal = StoryArcSpace.gutter,
            vertical = StoryArcSpace.md,
        ),
        horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.lg),
    ) {
        if (continueReading.isNotEmpty()) {
            item(span = { GridItemSpan(maxLineSpan) }, key = "continue-reading") {
                ContinueReadingRow(
                    continueReading,
                    viewModel,
                    onResume,
                    maxPixelSize,
                    onAddToShelf,
                )
            }
        }
        // `library-browsing`: while a search is running, results are "grouped by match
        // kind". One heading and one run of covers per group rather than a second screen —
        // the reader is looking at their library with a word typed over it, not somewhere
        // else.
        val cell: @Composable (Publication) -> Unit = { publication ->
            CoverCell(
                publication,
                viewModel,
                onOpen,
                maxPixelSize,
                onAddToShelf,
                isPicked = selection?.contains(publication.id),
                onToggle = onToggle,
            )
        }
        if (groups.isEmpty() && sections.isEmpty()) {
            items(publications, key = { it.id }) { cell(it) }
        } else if (groups.isEmpty()) {
            // One grid with headings pinned in it, rather than a second composable beside
            // this one. iOS had to split them — its grid lives inside its own `ScrollView`
            // and a pinned header has to share the lazy stack with the cells it heads — and
            // `LazyVerticalGrid` has no such problem: a full-span sticky item is a heading,
            // and the shelf keeps one scroll position, one column rule and one cell.
            for (section in sections) {
                stickyHeader(key = "section-${section.id}") {
                    SectionHeading(section.title)
                }
                items(section.publications, key = { it.id }) { cell(it) }
            }
        } else {
            for (group in groups) {
                item(span = { GridItemSpan(maxLineSpan) }, key = "heading-${group.kind}") {
                    MatchHeading(group.kind)
                }
                items(group.publications, key = { it.id }) { cell(it) }
            }
        }
    }
}

/**
 * One heading over its part of the shelf.
 *
 * On `surfaceOverlay` — the token the design system declares for chrome that has to be
 * opaque — rather than on the canvas, because a wall of covers slides under this: a
 * translucent band would show the artwork of whatever happened to be passing beneath the
 * words. A hairline separates it from the covers below.
 *
 * One line, even at the largest text size. A three-line heading pinned to the top of the
 * shelf would take more of the screen than the section it names. iOS's `SectionHeading` makes
 * both of the same choices for both of the same reasons.
 */
@Composable
private fun SectionHeading(title: String) {
    val palette = LocalStoryArcPalette.current
    Column(modifier = Modifier.fillMaxWidth().background(palette.surfaceOverlay)) {
        Text(
            text = title,
            style = MaterialTheme.typography.titleMedium,
            color = palette.textPrimary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.fillMaxWidth().padding(vertical = StoryArcSpace.sm),
        )
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(StoryArcSpace.hair)
                .background(palette.borderSubtle),
        )
    }
}

/**
 * Why the results under it matched.
 *
 * `library-browsing` asks for results "grouped by match kind — series, publication, person,
 * tag", which only means anything if the reader is told which group they are looking at.
 */
@Composable
internal fun MatchHeading(kind: MatchKind, modifier: Modifier = Modifier) {
    val palette = LocalStoryArcPalette.current
    Text(
        text = stringResource(kind.labelRes),
        style = MaterialTheme.typography.titleLarge,
        color = palette.textPrimary,
        modifier = modifier.fillMaxWidth().padding(top = StoryArcSpace.md),
    )
}

/**
 * How a match kind is named on screen.
 *
 * The kinds live in `:core:model` and carry no resources: the domain has no business
 * holding UI copy. Naming them is presentation, so it lives here — the same split iOS makes
 * with `titleKey`. Plural, because a heading names a set.
 */
private val MatchKind.labelRes: Int
    get() = when (this) {
        MatchKind.SERIES -> R.string.library_match_series
        MatchKind.PUBLICATION -> R.string.library_match_publication
        MatchKind.PERSON -> R.string.library_match_person
        MatchKind.TAG -> R.string.library_match_tag
    }

/**
 * What the reader was in the middle of.
 *
 * `library-browsing`: "a Continue reading row appears first, ordered by most
 * recently read". Horizontal, because it is a shortcut rather than a second
 * library — a vertical block of it would push the shelf off the screen.
 */
@Composable
private fun ContinueReadingRow(
    publications: List<Publication>,
    viewModel: LibraryViewModel,
    /** Opens the book itself. This row is a resume affordance, not a shelf of covers. */
    onResume: (Publication) -> Unit,
    maxPixelSize: Int,
    /** A long press, where a publication is put on a shelf. Null where there is nowhere to put it. */
    onAddToShelf: ((Publication) -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current
    val fontScale = LocalDensity.current.fontScale
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
    ) {
        Text(
            text = stringResource(R.string.library_continue_reading),
            style = MaterialTheme.typography.titleLarge,
            color = palette.textPrimary,
        )
        LazyRow(
            horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
        ) {
            items(publications, key = { it.id }) { publication ->
                CoverCell(
                    publication,
                    viewModel,
                    onResume,
                    maxPixelSize,
                    // The same long press the shelf below answers. A publication does not
                    // stop having collections because it is the one you were last
                    // reading, and until this was passed through, the row was the only
                    // cover in the app whose long press did nothing.
                    onAddToShelf = onAddToShelf,
                    // The same accessibility step the shelf below takes. A row of covers
                    // that kept its ordinary width while the grid under it widened would
                    // be the one place on the screen still truncating its captions — and
                    // it is the row the reader came back for. Unchanged at every ordinary
                    // font scale; iOS grows this row with the shelf for the same reason.
                    modifier = Modifier.width(CONTINUE_READING_WIDTH.steppedFor(fontScale)),
                )
            }
        }
    }
}

/** One publication in the grid. */
@Composable
@OptIn(ExperimentalFoundationApi::class)
private fun CoverCell(
    publication: Publication,
    viewModel: LibraryViewModel,
    onOpen: (Publication) -> Unit,
    maxPixelSize: Int,
    /** A long press, where a publication is put on a shelf. Null where there is nowhere to put it. */
    onAddToShelf: ((Publication) -> Unit)? = null,
    /** Whether this one is picked, or null when the library is not in selection mode. */
    isPicked: Boolean? = null,
    onToggle: (Publication) -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current
    var cover by remember(publication.id) { mutableStateOf<Bitmap?>(null) }

    LaunchedEffect(publication.id) {
        cover = viewModel.cover(publication, maxPixelSize)
    }

    val subtitle = cellSubtitle(publication)
    val isKept = viewModel.isOnDevice(publication)
    val isReadable = viewModel.isReadableNow(publication)
    // `library-browsing`: a publication that is neither on the device nor currently
    // reachable "is dimmed and still selectable", and "dimming is the only difference — it
    // is not moved, grouped apart, or badged as an error". Animated on Material's own
    // effects spec rather than a fixed duration, the way Home's cards are: a source coming
    // back should not make a cover flick to full brightness.
    val dim by animateFloatAsState(
        targetValue = if (isReadable) 1f else AWAY_ALPHA,
        animationSpec = MaterialTheme.motionScheme.defaultEffectsSpec(),
        label = "cover-cell-dim",
    )
    val unavailable = stringResource(R.string.library_cell_unavailable)
    val downloaded = stringResource(R.string.catalogue_entry_downloaded)

    Column(
        // One label for the whole cell. Read as three elements it would announce
        // the title, then the format, then an unlabelled image.
        modifier = modifier
            .fillMaxWidth()
            // Every cover is tappable, including one no decoder will open. It used not to
            // be, and the reasoning was sound while a tap opened the reader: showing the
            // same refusal a second time wasted the tap. A tap now opens the publication's
            // page, which is the screen that explains a refusal — `publication-detail`
            // gives it a primary action reading *Cannot be opened* with the reason under
            // it, and requires the page to be reachable "from every surface that shows a
            // publication". A cover with no way in would be the one hole in that.
            .then(
                when {
                    // While the reader is picking, a tap picks -- even a publication that
                    // cannot be opened, which can still be shelved and marked read. A cover
                    // that opened a page mid-selection would throw away every pick.
                    isPicked != null -> Modifier.clickable { onToggle(publication) }

                    // `collections-and-reading-lists`: a publication "may belong to any
                    // number of collections", and a long press is where a reader says so.
                    else -> Modifier.combinedClickable(
                        onClick = { onOpen(publication) },
                        onLongClick = { onAddToShelf?.invoke(publication) },
                    )
                },
            )
            .semantics {
                // No source. `library-browsing`: "nothing on the shelf states which source a
                // publication came from" — and a fact taken off the artwork but left in the
                // spoken label is the same leak, read aloud. The publication's own page
                // carries the one provenance line, for every reader alike.
                contentDescription = listOfNotNull(
                    publication.displayTitle,
                    subtitle,
                    publication.format.displayName,
                    // Spoken for the reason the progress is: a mark in the corner of a cover
                    // is invisible to TalkBack, and "can I read this on the train" is the
                    // whole question the mark answers. Spoken even while picking, when the
                    // mark itself stands down. The wording is the one the catalogue already
                    // uses for the same state, in the four languages it is already
                    // translated into.
                    downloaded.takeIf { isKept },
                    // And dimming is invisible to TalkBack as well, which is the half of
                    // this the requirement is explicit about: the accessibility label
                    // carries the fact, not the opacity.
                    unavailable.takeIf { !isReadable },
                ).joinToString(", ")
                // Spoken, because a tick in the corner of a cover is invisible to
                // TalkBack and "is this one picked" is the only question selection mode
                // asks.
                if (isPicked != null) selected = isPicked
            },
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xs),
    ) {
        Surface(
            // 2:3 is the comic and book proportion. Fixing it here means a cell
            // reserves its space before its cover arrives, so the grid does not
            // reflow as images land.
            //
            // The dim is on the artwork alone. The caption under it stays legible, because a
            // publication a reader cannot open right now is still one they have to be able
            // to read the title of in order to shelve it or queue it.
            modifier = Modifier.fillMaxWidth().aspectRatio(2f / 3f).alpha(dim),
            // `design.md` §4: art "letterboxes onto `surfaceSunken` rather than being
            // distorted". This is the well the letterbox bars show, which is why it is the
            // sunken role and not the raised one — the cover sits *in* the cell.
            color = palette.surfaceSunken,
            // 4 dp, not 10. `design.md` §4: "Cover radius stays at 4 pt on purpose. A
            // comic cover is printed stock. Rounding it like an app icon reads as wrong,
            // and every reader app that does it looks like a music player."
            shape = RoundedCornerShape(StoryArcRadius.cover),
        ) {
            val fraction = viewModel.readFraction(publication)
            val bitmap = cover
            if (bitmap != null) {
                Image(
                    bitmap = bitmap.asImageBitmap(),
                    contentDescription = null,
                    // Fit, not Crop. A manga volume is taller than 2:3 and a square EPUB
                    // cover is not close to it; cropping to the cell cut the edges off
                    // artwork the reader is using to recognise the book. The bars this
                    // leaves fall on `surfaceSunken` above, which is the letterbox.
                    contentScale = ContentScale.Fit,
                    modifier = Modifier
                        .fillMaxSize()
                        .clip(RoundedCornerShape(StoryArcRadius.cover)),
                )
            } else {
                // A set title rather than an empty rectangle. A grid of publications
                // with no cover art -- and plenty of EPUBs carry none -- was a wall of
                // identical cards labelled with a format, which is the one thing every
                // card in that wall had in common. The title is what tells them apart.
                // The format stays, smaller, because it is still the answer to "why is
                // there no picture".
                Box(modifier = Modifier.fillMaxSize()) {
                    Text(
                        text = publication.displayTitle,
                        style = MaterialTheme.typography.titleSmall,
                        color = palette.textSecondary,
                        textAlign = TextAlign.Center,
                        maxLines = 4,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier
                            .align(Alignment.Center)
                            .padding(horizontal = StoryArcSpace.sm),
                    )
                    Text(
                        text = publication.format.displayName,
                        style = MaterialTheme.typography.labelSmall,
                        color = palette.textTertiary,
                        modifier = Modifier
                            .align(Alignment.BottomCenter)
                            .padding(bottom = StoryArcSpace.xs),
                    )
                }
            }

            // `library-browsing`: "its cover carries an unobtrusive progress
            // indicator", and "a fully read publication is distinguishable at a
            // glance without a label covering the artwork". A bar along the foot
            // does both — it never crosses the artwork, and a full one reads as
            // finished without a word on top of the cover.
            if (fraction != null) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .wrapContentHeight(Alignment.Bottom),
                ) {
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .height(3.dp)
                            .background(Color.Black.copy(alpha = 0.35f)),
                    )
                    Box(
                        Modifier
                            .fillMaxWidth(fraction.coerceIn(0f, 1f))
                            .height(3.dp)
                            .background(
                                if (fraction >= 1f) palette.textSecondary else palette.accent,
                            ),
                    )
                }
            }

            if (isPicked != null) {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.TopEnd) {
                    PickMark(isPicked)
                }
            }

            // `design.md` asks for "downloaded state as a small filled mark in one corner",
            // and the palette calls `status/downloaded` "the one badge permitted to compete
            // with cover art".
            //
            // Not while picking. `library-browsing` lets a cover carry "at most two marks:
            // how far the reader has got, and whether it can be read with no network", and
            // "no third mark is added to a cover for any reason" — so the pick mark is not
            // an addition to that pair, it is a substitution into it. This one is what
            // gives, because availability answers a browsing question and the reader has
            // stopped browsing: the only question selection mode asks is which covers are
            // picked. The progress rail stays, because it is the rail along the artwork's
            // foot rather than a second glyph in the corners, and because how far in a cover
            // is remains how a reader finds the ones they meant to pick.
            //
            // Spoken either way, in the label below. A mark withheld to keep the artwork
            // legible is not a fact withheld. iOS's `CoverCell.showsOnDeviceMark` is the
            // same rule.
            if (isPicked == null && isKept) {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.BottomEnd) {
                    OnDeviceMark()
                }
            }
        }

        Column(verticalArrangement = Arrangement.spacedBy(StoryArcSpace.hair)) {
            Text(
                text = publication.displayTitle,
                style = MaterialTheme.typography.bodyMedium,
                color = palette.textPrimary,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            if (subtitle != null) {
                Text(
                    text = subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = palette.textTertiary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            // No third line naming a server. `library-browsing` now requires that "nothing
            // on the shelf states which source a publication came from": origin stopped
            // being how a reader narrows the library, so a grey line under every cover was
            // the management surface leaking into the discovery one. The publication's own
            // page carries the one provenance line instead, which is where a reader asks
            // the question. iOS's `CoverCell` dropped the same line.
        }
    }
}

/**
 * Whether a cover is one of the ones the reader has picked.
 *
 * A mark in the corner rather than a tint over the artwork: the artwork is the interface, and
 * a wash of accent colour across a cover hides the one thing the reader is using to tell it
 * from its neighbour.
 *
 * iOS's `PickMark` sits in the same corner.
 *
 * `library-browsing` lets a cover carry "at most two marks: how far the reader has got, and
 * whether it can be read with no network", and forbids a third "for any reason". This grid
 * spends one on the progress rail and has no downloaded mark yet, so the tick fits. Whoever
 * draws that mark here inherits iOS's rule with it: while the reader is picking, the pick
 * mark takes the downloaded mark's place rather than joining it.
 */
@Composable
internal fun PickMark(isPicked: Boolean, modifier: Modifier = Modifier) {
    val palette = LocalStoryArcPalette.current
    Icon(
        imageVector = if (isPicked) Icons.Filled.CheckCircle else Icons.Outlined.Circle,
        // Announced by the cell, which already speaks the title this belongs to.
        contentDescription = null,
        tint = if (isPicked) palette.accent else palette.textTertiary,
        modifier = modifier.padding(StoryArcSpace.xs),
    )
}

/**
 * Whether this cover can be read with no network, said in one corner.
 *
 * `design.md` asks for "downloaded state as a small filled mark in one corner", and the
 * palette calls `status/downloaded` "the one badge permitted to compete with cover art".
 * That is the other question a shelf is asked besides how far in the reader got — can I read
 * this on the train — and it is the axis the library's own scope control is built on, so it
 * had better be visible on the covers.
 *
 * Filled, on its own ground, and the only status colour in the grid. A glyph on a disc reads
 * over any artwork; an unfilled one is a shape lost in whatever the cover happens to be. The
 * disc takes `surfaceCanvas` so the mark is legible in both appearances without a shadow.
 *
 * It stands down while the reader is picking — see the call site, and iOS's
 * `CoverCell.showsOnDeviceMark` for the same rule stated as a property.
 *
 * No description: the cell speaks this in its own label, and a second announcement would
 * make one cover two stops for a screen reader.
 */
@Composable
internal fun OnDeviceMark(modifier: Modifier = Modifier) {
    val palette = LocalStoryArcPalette.current
    Box(
        modifier = modifier.padding(StoryArcSpace.xs),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            modifier = Modifier
                .size(ON_DEVICE_MARK_SIZE)
                .clip(CircleShape)
                .background(palette.surfaceCanvas),
        )
        Icon(
            imageVector = Icons.Filled.CheckCircle,
            contentDescription = null,
            tint = StoryArcColor.Status.downloaded,
            modifier = Modifier.size(ON_DEVICE_MARK_SIZE),
        )
    }
}

/** Large enough to read over artwork, small enough not to be a second thing on the cover. */
private val ON_DEVICE_MARK_SIZE = 18.dp

/** The second line: what distinguishes this cell from its neighbours. */
@Composable
private fun cellSubtitle(publication: Publication): String? = when {
    // Said plainly rather than shown as a broken cover. `publication-formats`
    // requires a named refusal, and a grid cell is where a user meets one.
    !publication.isOpenable -> stringResource(R.string.library_cell_cannot_open)

    // The same rule the list caption uses, from the same function. A cell headed
    // `Harbour Lights #1` captioning itself `Harbour Lights #1` was the defect; comparing
    // the composed line rather than the bare series name is the fix.
    else -> seriesLine(publication) ?: publication.authors.firstOrNull()
}
