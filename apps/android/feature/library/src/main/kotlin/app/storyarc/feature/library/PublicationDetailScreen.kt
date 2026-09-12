package app.storyarc.feature.library

import android.graphics.Bitmap
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LargeFlexibleTopAppBar
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.adaptive.ExperimentalMaterial3AdaptiveApi
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfoV2
import androidx.compose.material3.adaptive.layout.PaneAdaptedValue
import androidx.compose.material3.adaptive.layout.SupportingPaneScaffold
import androidx.compose.material3.adaptive.layout.ThreePaneScaffoldValue
import androidx.compose.material3.adaptive.layout.calculatePaneScaffoldDirective
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.storyarc.core.format.PublicationAccess
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Download
import app.storyarc.core.model.Publication
import app.storyarc.core.model.ReadingAddress

/** Enough pixels for the largest the cover is ever drawn, on the densest screen. */
private const val DETAIL_COVER_PIXELS = 1200

/**
 * Below this the window is short, and the page stops spending height it does not have.
 *
 * Material's compact *height* class. A landscape phone is 360 dp tall and a 152 dp app bar
 * over an 88 dp navigation bar left the book 96 dp — see [DetailHeroLayout] for what that
 * did to the one action the screen exists for.
 */
private val SHORT_WINDOW_HEIGHT = 480.dp

/**
 * The page a publication has.
 *
 * `publication-detail` calls this the seam, and the word is load-bearing.
 * `library-browsing` presents five kinds of source as one library and takes origin off the
 * shelf entirely — no per-source destinations, no server chips, no source line under a
 * cover. That argument only works because origin is *here*: one line, at the foot of the
 * information, naming where this publication lives and whether it can be opened now. Take
 * this screen away and a reader who owns the same volume locally and on a server cannot
 * tell which one they are about to open.
 *
 * It is also the app's only screen between the shelf and the reader, so everything that is
 * not reading lives here.
 *
 * **Built Material's way, not as a port of the iOS layout.** The direction's divergence
 * register is the authority for each move:
 *
 * - `LargeFlexibleTopAppBar` with a **subtitle**, collapsing onto the cover, rather than a
 *   large title typeset into the content. The delta wants title, series and year to read as
 *   one object; the flexible bars grew a subtitle slot for exactly that (#9).
 * - Emphasis by **shape break and containment**, not by a prominent tinted control — the
 *   register's answer to iOS's `.glassProminent` (#10), and the one that does not tint
 *   artwork.
 * - Secondary actions in an **overflow menu**, with add-to-a-shelf as a **modal bottom
 *   sheet** (#7), which is already the shape this app uses everywhere else.
 * - `SupportingPaneScaffold` for the tablet presentation (#4, #5), so a wide window reads
 *   the series beside the book rather than under it.
 * - Motion from `MaterialTheme.motionScheme` rather than from fixed durations (#11).
 *
 * **Dynamic colour never reaches this page's content.** The direction scopes Material You
 * to chrome, and the delta says the cover's colour "reaches the page's content surfaces
 * only" while "navigation, toolbars and any floating chrome stay as `native-experience`
 * requires". Both rules point the same way and this screen keeps them: the app bar takes
 * Material's own colours and no cover's, and the hero takes the cover's and no wallpaper's.
 * A tinted bar that changed hue as the reader moved between publications is the failure
 * both rules exist to prevent.
 */
@OptIn(
    ExperimentalMaterial3Api::class,
    ExperimentalMaterial3ExpressiveApi::class,
    ExperimentalMaterial3AdaptiveApi::class,
)
@Composable
fun PublicationDetailScreen(
    publication: Publication,
    viewModel: LibraryViewModel,
    /** Whether a copy is on this device — a download, an import, or a file in a scanned folder. */
    isOnDevice: Boolean,
    /**
     * Whether the shelf is permanently beside this page, as the list half of two panes.
     *
     * When it is, the bar draws no back arrow. There is nowhere to go back *to*: the list
     * the arrow would return to has never left the window, and Material's own
     * `ListDetailPaneScaffold` hides the affordance for exactly that reason. This page is
     * composed into a hand-built pair of panes, so it carries the rule itself.
     *
     * [onBack] is still called — by the system gesture, and by the "this is gone" screen's
     * own button, which does have somewhere to go: back to the pane's one sentence.
     */
    isBesideList: Boolean = false,
    /**
     * The queue's own record for a transfer of this publication, or null when there is none.
     *
     * The record rather than the fraction it used to be, because a fraction cannot say why
     * nothing is moving. `publication-detail`'s *Downloading from here* asks for both from one
     * state -- "a transfer that is waiting says what it is waiting for", and progress "as soon
     * as the library states a size" -- and only the record carries the pause reason.
     *
     * A copy started from this page arrives through [queue] instead, and that one wins: see
     * [PublicationCopy.record] for why the two are looked up under different ids.
     */
    transfer: Download? = null,
    /**
     * The catalogue this publication's row came from, or null for a row from anywhere else.
     *
     * With [queue], the whole copy route. `publication-detail` requires the copy to join "the
     * same queue as every other download" so that "the transfer continues after the reader
     * leaves the page", and neither the source registry nor the credential store is reachable
     * from this module -- so what the app layer hands down is the page it already builds to
     * browse the same catalogue.
     */
    page: CataloguePage? = null,
    /** The app's one download queue. Null where this publication has no copy to obtain. */
    queue: DownloadQueue? = null,
    /**
     * The parts an audiobook plays in, as `AudiobookChapters.parts` reports them.
     *
     * Empty for everything that is not an audiobook, and empty until the container has been
     * read — a page that has no chapters yet draws no list rather than an empty one.
     */
    chapters: List<AudiobookPart> = emptyList(),
    /**
     * The part the listener stopped in, or null for an audiobook they never started.
     *
     * The same fact the primary action reads as *has progress*, so the button and the marks
     * on the list cannot disagree about whether the book was started.
     */
    stoppedIn: Int? = null,
    /**
     * How far into [stoppedIn] the listener got, so the chapter in progress states what is
     * left of it. Zero for an audiobook nobody started, which marks no chapter anyway.
     */
    offsetMillis: Long = 0,
    /**
     * Whether this publication is finished, so every chapter of it is marked finished.
     *
     * Beside [stoppedIn] rather than folded into it: a finished audiobook offers to start
     * again, so the saved position it resumes from is null and the marks would otherwise read
     * as a book nobody had opened. See [chapterRows].
     */
    isFinished: Boolean = false,
    /**
     * A chapter was chosen: start there rather than where the book was left.
     *
     * A different verb from [onRead], which resumes. `audio-playback` asks for both, and for
     * looking at the list to leave the saved position alone — which it does, because this
     * page never writes one.
     */
    onListenFrom: (Int) -> Unit = {},
    /**
     * Open the book, at the start or where the reader stopped.
     *
     * The second argument is the whole answer to *where*: the copy this page holds, the
     * library's own location, or -- while a transfer of this publication is running -- the
     * address it is being fetched from, which `offline-downloads` asks to be readable before
     * the bytes land. [ReadingAddress] decides between them, and null means there is nothing
     * to open, in which case this is never called.
     */
    onRead: (Publication, String?) -> Unit,
    /** Another publication's own page. A cover is the detail verb everywhere in this app. */
    onOpenPage: (Publication) -> Unit,
    onMark: (Publication, Boolean) -> Unit,
    /**
     * Fetch a copy onto the device from an address the app can already read.
     *
     * A share, in practice: [DownloadQueue] transfers with `OpdsClient`, which refuses every
     * scheme that is not `http` or `https`, so a publication on an SMB share keeps the app
     * layer's own route. Disjoint from [queue] by construction -- a row with a location is
     * never a row with a catalogue entry to fetch -- and null where the app has no route at
     * all.
     *
     * **Named for the route rather than for the button, because passing it to a button is the
     * defect this name prevents.** It is one of the two ways to a copy; `obtain` is both, and
     * `obtain` is what the controls take. Handing this straight to a control drew no control
     * at all for every catalogue row, since a catalogue row reaches its copy the other way.
     */
    onCopyFromLocation: (() -> Unit)? = null,
    /** Remove the copy on the device. Null where there is none to remove. */
    onRemoveDownload: (() -> Unit)? = null,
    onBack: () -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    val registry by viewModel.registry.collectAsStateWithLifecycle()
    val library by viewModel.publications.collectAsStateWithLifecycle()

    var cover by remember(publication.id) { mutableStateOf<Bitmap?>(null) }
    LaunchedEffect(publication.id) {
        cover = viewModel.cover(publication, DETAIL_COVER_PIXELS)
    }
    val accent = rememberDetailAccent(cover)

    // The copy route, and the mobile-data question it has to ask. Before the action, because
    // a copy that lands while the page is open changes what the action *is*.
    val copy = rememberPublicationCopy(publication, page, queue)

    // **A copy the queue finished is on the device, whatever the library's table says.**
    // `adoptDownloads` folds a finished download onto a library row by identity, and an OPDS
    // row carries a server identifier and no path, so it can match nothing until the file is
    // scanned. Without this the delta's "the copy arrives while the page is open" scenario
    // could not happen at all: the page would go on asking for a copy it already had.
    val isHere = isOnDevice || copy.file != null

    // Where this publication opens, if it opens at all.
    //
    // **`offline-downloads`' *Reading while downloading*.** A transfer that has started names
    // an address the ranged reader can open, so a publication that is still downloading opens
    // now instead of after four hundred megabytes. The rule is [ReadingAddress]'s and is
    // asserted there; iOS asks the same one.
    //
    // Which readers can open an address is the platform's truth and therefore the screen's to
    // state, which is what [readsFromAnAddress] answers.
    val where = ReadingAddress.of(
        local = copy.file?.path ?: viewModel.location(publication),
        transfer = copy.record ?: transfer,
        readsWhereItLies = readsFromAnAddress(publication),
    )
    // `isStreamed` rather than `PublicationAccess.isRemote` alone for the arriving case: the
    // second answers from a registry the app fills at start-up, so a screen that asked only
    // that would offer a download or a read depending on start-up order. What the address *is*
    // does not depend on who has registered what.
    val readsWhereItLies = isHere ||
        (where != null && (ReadingAddress.isStreamed(where) || PublicationAccess.isRemote(where)))

    val provenance = provenanceOf(publication, registry, isHere, library)
    val hasProgress = viewModel.readFraction(publication) != null
    val action = primaryActionOf(publication, provenance, isHere, hasProgress, readsWhereItLies)
    val series = remember(publication.id, library) { restOfSeries(publication, library) }

    // A stale shortcut, a removed source, a deleted file: the publication the page was
    // opened for is no longer anywhere. The delta refuses an empty page for this, and the
    // page has nothing honest to draw, so it says the one true sentence instead.
    //
    // An empty library is *not* an absent publication. The list arrives asynchronously and
    // starts empty, so without this guard every page would claim the book was gone for the
    // frame before the library loaded — and a reader who reached this page from a cover
    // came from a library that had at least that one thing in it.
    val isGone = library.isNotEmpty() && library.none { it.id == publication.id } && !isHere
    if (isGone) {
        DetailGone(onBack = onBack)
        return
    }

    var isMenuOpen by remember { mutableStateOf(false) }
    var isShelfSheetOpen by remember { mutableStateOf(false) }
    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()
    val density = LocalDensity.current
    val windowHeight = with(density) { LocalWindowInfo.current.containerSize.height.toDp() }
    // A `LargeFlexibleTopAppBar` carrying a subtitle is 152 dp whatever the window is, so on
    // a landscape phone it and the navigation bar were two thirds of the screen and the page
    // had 96 dp to draw a book in. Material's compact *height* class is where a large bar
    // stops being an editorial flourish and starts being the screen.
    val isShort = windowHeight < SHORT_WINDOW_HEIGHT

    // One verb for obtaining the copy, whichever route this publication has. The queue is
    // preferred and the two are disjoint anyway: `copy.start` exists only for a catalogue row,
    // which by definition has no location for [onCopyFromLocation] to fetch from.
    //
    // **Both controls below take this, and taking the other one was a dead end a reader met.**
    // They took `onCopyFromLocation`, which is null for every catalogue row, so a publication
    // fetched from a catalogue drew *This one has to be on your device before it opens* and
    // offered nothing that could put it there — not as the primary action, not in the
    // overflow. Measured on an emulator on 2026-09-12, with the copy route resolved and its
    // acquisition in hand: the page had the verb and handed the buttons the other one.
    val obtain = copy.start ?: onCopyFromLocation

    // Decided once, here, and handed to exactly one of the two controls below. The primary
    // and the overflow used to reach for `onDownload` independently, so a publication that
    // has to arrive before it opens offered *Download it* twice -- once as the thing the
    // page wants you to do and once buried in the menu beside it.
    val download = downloadControl(action, canDownload = obtain != null)

    Scaffold(
        containerColor = palette.surfaceCanvas,
        modifier = Modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        topBar = {
            val back: @Composable () -> Unit = {
                if (!isBesideList) {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.detail_back),
                        )
                    }
                }
            }
            val overflow: @Composable RowScope.() -> Unit = {
                IconButton(onClick = { isMenuOpen = true }) {
                    Icon(
                        imageVector = Icons.Filled.MoreVert,
                        contentDescription = stringResource(R.string.detail_more),
                    )
                }
                DetailOverflowMenu(
                    isOpen = isMenuOpen,
                    onDismiss = { isMenuOpen = false },
                    isFinished = publication.id in viewModel.finishedPublications(),
                    onMark = { isRead -> onMark(publication, isRead) },
                    onAddToShelf = { isShelfSheetOpen = true },
                    onDownload = obtain.takeIf { download == DownloadControl.OVERFLOW },
                    onRemoveDownload = onRemoveDownload,
                )
            }
            if (isShort) {
                // The subtitle goes with the large bar. It repeats the series, which the
                // page states again below, and on a 360 dp window it costs 40 dp the book
                // needs more.
                TopAppBar(
                    title = { DetailTitle(publication) },
                    navigationIcon = back,
                    actions = overflow,
                    scrollBehavior = scrollBehavior,
                )
            } else {
                LargeFlexibleTopAppBar(
                    title = { DetailTitle(publication) },
                    subtitle = { DetailSubtitle(publication) },
                    navigationIcon = back,
                    actions = overflow,
                    scrollBehavior = scrollBehavior,
                )
            }
        },
    ) { insets ->
        val directive = calculatePaneScaffoldDirective(currentWindowAdaptiveInfoV2())
        val main: @Composable (Modifier, DetailHeroLayout) -> Unit = { modifier, hero ->
            DetailMainPane(
                publication = publication,
                cover = cover,
                accent = accent,
                hero = hero,
                action = action,
                provenance = provenance,
                transfer = transfer,
                chapters = chapters,
                stoppedIn = stoppedIn,
                offsetMillis = offsetMillis,
                isFinished = isFinished,
                onRead = { onRead(publication, where) },
                onListenFrom = onListenFrom,
                onDownload = obtain.takeIf { download == DownloadControl.PRIMARY },
                modifier = modifier,
            )
        }
        val supporting: @Composable (Modifier) -> Unit = { modifier ->
            DetailSeriesShelf(
                publications = series,
                viewModel = viewModel,
                onOpen = onOpenPage,
                modifier = modifier,
            )
        }

        // The room the page actually has, measured rather than derived: the app bar's height
        // is Material's and the navigation bar is taken out before this page is laid out at
        // all, so the only honest way to ask is to be told. Outside the scroll, because
        // inside one the height constraint is infinite and the question has no answer.
        BoxWithConstraints(modifier = Modifier.fillMaxSize().padding(insets)) {
            val hero = DetailHeroLayout.of(windowHeight, maxHeight)
            if (directive.maxHorizontalPartitions > 1) {
                // The delta's "two panes": the series reads beside the book rather than under
                // it. The scaffold, rather than a hand-rolled `Row`, because it is what carries
                // Material's own partition sizes and spacer, and because the same component is
                // what the library will host this page inside once it adopts the list-detail
                // scaffold.
                SupportingPaneScaffold(
                    directive = directive,
                    value = ThreePaneScaffoldValue(
                        primary = PaneAdaptedValue.Expanded,
                        secondary = PaneAdaptedValue.Expanded,
                        tertiary = PaneAdaptedValue.Hidden,
                    ),
                    mainPane = { main(Modifier.verticalScroll(rememberScrollState()), hero) },
                    supportingPane = { supporting(Modifier.verticalScroll(rememberScrollState())) },
                    modifier = Modifier.fillMaxSize(),
                )
            } else {
                // One pane, one column, and the series under the book. Not the scaffold with a
                // hidden pane: a hidden supporting pane is a shelf the reader cannot reach, and
                // the shelf is required on every window size.
                Column(
                    verticalArrangement = Arrangement.spacedBy(StoryArcSpace.section),
                    modifier = Modifier
                        .fillMaxSize()
                        .verticalScroll(rememberScrollState())
                        .padding(horizontal = StoryArcSpace.gutter, vertical = StoryArcSpace.lg),
                ) {
                    main(Modifier, hero)
                    supporting(Modifier)
                }
            }
        }
    }

    if (isShelfSheetOpen) {
        // Divergence #7: add-to-a-shelf is a modal bottom sheet on Android and a menu on
        // iOS, and both are the platform-idiomatic shape. The sheet already exists and
        // already carries mark-read, so this page grew no second copy of either.
        AddToShelfSheet(
            viewModel = viewModel,
            publications = listOf(publication),
            onDismiss = { isShelfSheetOpen = false },
            onMark = { publications, isRead -> publications.forEach { onMark(it, isRead) } },
        )
    }
}

/**
 * Everything about the book itself: the cover over its colour, the one action, what it is,
 * and where it came from.
 *
 * The provenance line is last, quiet, and at the foot of the information — which is where
 * the delta puts it and why every other browse surface is allowed to say nothing about
 * origin at all.
 */
// `internal` rather than `private` for one reason, and it is the wiring: `KavitaCardFactsTest`
// composes this pane to assert that a downloaded Kavita title's status and rating actually
// reach the page. Asserting the block draws them in isolation would leave the one edit that
// reintroduces the defect -- deleting the call below -- passing every test in the module.
@Composable
internal fun DetailMainPane(
    publication: Publication,
    cover: Bitmap?,
    accent: DetailAccent?,
    /** How the hero arranges itself in the room the page has. See [DetailHeroLayout]. */
    hero: DetailHeroLayout = DetailHeroLayout(isSideBySide = false, coverHeight = 360.dp),
    action: PrimaryAction,
    provenance: Provenance,
    transfer: Download? = null,
    chapters: List<AudiobookPart> = emptyList(),
    stoppedIn: Int? = null,
    offsetMillis: Long = 0,
    isFinished: Boolean = false,
    onRead: () -> Unit,
    onListenFrom: (Int) -> Unit = {},
    onDownload: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current
    // The format is asked here rather than at the call site. "A comic never grows a chapter
    // list" is a rule about this page, and a rule enforced by whoever remembers to write the
    // `if` is a rule one caller gets wrong. iOS asks it in `DetailChapters.of(_:parts:)` for
    // the same reason.
    val parts = if (publication.format.isAudio) chapters else emptyList()
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.lg),
    ) {
        DetailHero(publication = publication, cover = cover, accent = accent, layout = hero) {
            DetailPrimaryAction(
                action = action,
                accent = accent,
                resumeChapter = resumeChapterTitle(parts, stoppedIn),
                onRead = onRead,
                onDownload = onDownload,
            )
        }

        // `offline-downloads` allows reading while downloading, so this is progress rather
        // than a gate: the primary action above stays exactly as usable as it was.
        // `offline-downloads` allows reading while downloading, so this is progress rather
        // than a gate: the primary action above stays exactly as usable as it was.
        //
        // The record rather than a bare fraction, because one number cannot say all three
        // things `publication-detail`'s *Downloading from here* asks for. A held transfer
        // states what it is waiting for and is **not** described as downloading, which a
        // fraction alone could never avoid saying. And a size the library never stated is an
        // indeterminate bar, not a bar at zero: `offline-downloads` calls a fabricated size
        // worse than an honest blank.
        transfer?.let { record ->
            val paused = record.state as? Download.State.Paused
            val waiting = when (paused?.reason) {
                Download.Pause.WAITING_FOR_WIFI -> stringResource(R.string.downloads_paused_waiting_for_wifi)
                Download.Pause.OUT_OF_SPACE -> stringResource(R.string.downloads_paused_out_of_space)
                // A pause the reader asked for needs no sentence: they know, and the control
                // that resumes it is in the downloads view where they paused it.
                Download.Pause.BY_READER, null -> null
            }
            Column(verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xs)) {
                Text(
                    text = waiting ?: stringResource(R.string.detail_downloading),
                    style = MaterialTheme.typography.labelMedium,
                    color = palette.textSecondary,
                )
                val fraction = record.fraction
                if (fraction != null) {
                    LinearProgressIndicator(
                        progress = { fraction.toFloat() },
                        modifier = Modifier.fillMaxWidth(),
                    )
                } else {
                    LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                }
            }
        }

        publication.summary?.takeIf { it.isNotBlank() }?.let { summary ->
            Text(
                text = summary,
                style = MaterialTheme.typography.bodyMedium,
                color = palette.textSecondary,
            )
        }

        // Under the summary and above the provenance line, which stays last. A listener
        // choosing what to hear next reads what the book is, then what is in it.
        DetailChapters(
            parts = parts,
            stoppedIn = stoppedIn,
            onChoose = onListenFrom,
            offsetMillis = offsetMillis,
            isFinished = isFinished,
        )

        // The two of `kavita-server`'s seven metadata fields that `Publication` has no slot
        // for. Absent for everything that is not a kept Kavita chapter, which is most of the
        // shelf. See `KavitaCardFacts`.
        KavitaCardFacts(publication.id)

        ProvenanceLine(provenance)
    }
}

/**
 * The one thing the page wants the reader to do, and a sentence when it cannot.
 *
 * First control after the title in the reading order, which the design's accessibility note
 * calls an accessibility feature rather than a layout preference: its label says which of
 * *read* and *continue* will happen, so a screen-reader user learns the outcome before
 * taking it.
 *
 * @param resumeChapter the chapter a resume lands inside, which `audio-playback` asks the
 *   action to name. Null where naming one would say nothing: a book never started, a book
 *   with one part, and everything that is not an audiobook.
 */
@Composable
private fun DetailPrimaryAction(
    action: PrimaryAction,
    accent: DetailAccent?,
    resumeChapter: String?,
    onRead: () -> Unit,
    onDownload: (() -> Unit)?,
) {
    val palette = LocalStoryArcPalette.current
    val scheme = MaterialTheme.colorScheme
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
    ) {
        // Two independent facts, and both have to hold. [PrimaryAction.label] is null for
        // the one state that never has a button; `press` is null when the state would have
        // one and the app has no way to act on it — a publication that has to be fetched
        // from a source that offers no route to a copy. That one keeps its explanation and
        // loses its button, which is the same "absent, not disabled" rule from the other
        // side.
        val press: (() -> Unit)? = if (action.opensTheBook) onRead else onDownload
        val label = action.label()
        if (press != null && label != null) {
            Button(
                onClick = press,
                shape = MaterialTheme.shapes.large,
                colors = ButtonDefaults.buttonColors(
                    // The cover's own accent, already adjusted until it clears the 3:1
                    // floor against the wash it is drawn on — never the raw extracted
                    // colour, which the delta forbids outright. The brand accent where the
                    // cover yielded nothing, which is `native-experience`'s answer for a
                    // surface with no publication colour of its own.
                    containerColor = accent?.accent ?: scheme.primary,
                    contentColor = accent?.onAccent ?: scheme.onPrimary,
                ),
                modifier = Modifier.fillMaxWidth(),
            ) {
                // The chapter, where there is one to name. `audio-playback`: the action
                // "names the chapter it will resume inside". The bare label stays for every
                // other state, so no wording is decided twice.
                Text(
                    if (action == PrimaryAction.CONTINUE_LISTENING && resumeChapter != null) {
                        stringResource(
                            R.string.detail_action_continue_listening_chapter,
                            resumeChapter,
                        )
                    } else {
                        stringResource(label)
                    },
                )
            }
        }
        action.explanation()?.let { explanation ->
            Text(
                text = stringResource(explanation),
                style = MaterialTheme.typography.bodySmall,
                color = palette.textSecondary,
            )
        }
    }
}

/**
 * Everything that is not reading.
 *
 * `publication-detail`: each of these is "available from this page without competing with
 * the primary action", and "an action that does not apply is absent, not shown disabled
 * without explanation". So download and remove-download are `null` rather than greyed when
 * the app has no way to perform them.
 */
@Composable
private fun DetailOverflowMenu(
    isOpen: Boolean,
    onDismiss: () -> Unit,
    isFinished: Boolean,
    onMark: (Boolean) -> Unit,
    onAddToShelf: () -> Unit,
    onDownload: (() -> Unit)?,
    onRemoveDownload: (() -> Unit)?,
) {
    DropdownMenu(expanded = isOpen, onDismissRequest = onDismiss) {
        DropdownMenuItem(
            text = { Text(stringResource(R.string.detail_add_to_shelf)) },
            onClick = {
                onDismiss()
                onAddToShelf()
            },
        )
        DropdownMenuItem(
            text = {
                Text(
                    stringResource(
                        if (isFinished) R.string.library_mark_unread else R.string.library_mark_read,
                    ),
                )
            },
            onClick = {
                onDismiss()
                onMark(!isFinished)
            },
        )
        onDownload?.let { download ->
            DropdownMenuItem(
                text = { Text(stringResource(R.string.detail_action_download)) },
                onClick = {
                    onDismiss()
                    download()
                },
            )
        }
        onRemoveDownload?.let { remove ->
            DropdownMenuItem(
                text = { Text(stringResource(R.string.downloads_remove)) },
                onClick = {
                    onDismiss()
                    remove()
                },
            )
        }
    }
}

/**
 * The publication the page was opened for is not there any more.
 *
 * The delta asks for the reader to be returned "with a plain sentence saying it is gone".
 * The shell has no snackbar host above a destination's screens, so returning *and* saying
 * it would mean inventing one here — which is the app layer's business and another slice's
 * file. One plain sentence and the way back is the honest half of that, and it is still
 * emphatically not an empty page. The handoff records the rest.
 */
@Composable
private fun DetailGone(onBack: () -> Unit) {
    val palette = LocalStoryArcPalette.current
    Column(
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
        modifier = Modifier.fillMaxSize().padding(StoryArcSpace.xxl),
    ) {
        Text(
            text = stringResource(R.string.detail_gone_title),
            style = MaterialTheme.typography.headlineSmall,
            color = palette.textPrimary,
        )
        Text(
            text = stringResource(R.string.detail_gone_body),
            style = MaterialTheme.typography.bodyMedium,
            color = palette.textSecondary,
        )
        Button(onClick = onBack, modifier = Modifier.padding(top = 8.dp)) {
            Text(stringResource(R.string.detail_gone_back))
        }
    }
}

/**
 * The second pane, before a publication has been chosen.
 *
 * `publication-detail`: "the second pane says so in one sentence rather than showing an
 * arbitrary publication or an empty rectangle". Both of the things it forbids are worse
 * than they sound — an arbitrary publication is the app claiming the reader chose
 * something, and an empty rectangle is half a tablet of nothing with nothing said about it.
 *
 * Android had a third answer, which was to hide the pane until something went in it. It is
 * out because the shelf reflowed when the pane arrived: the column count changed under the
 * reader on their first tap and changed back on their last press of Back, which is the
 * library rearranging itself in answer to something that was not about the library. §4.7 of
 * the direction settles it from the other side — "expanded and above: two panes" — and a
 * pane that is only sometimes there is not two panes.
 *
 * The wording is iOS's, to the word, in the four languages the app speaks. One situation
 * described twice is how a four-language app comes apart, and this is one situation.
 */
@Composable
fun PublicationPanePlaceholder(modifier: Modifier = Modifier) {
    val palette = LocalStoryArcPalette.current
    Column(
        modifier = modifier.fillMaxSize().padding(StoryArcSpace.xxl),
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            text = stringResource(R.string.detail_pane_empty),
            style = MaterialTheme.typography.bodyLarge,
            color = palette.textSecondary,
        )
    }
}
