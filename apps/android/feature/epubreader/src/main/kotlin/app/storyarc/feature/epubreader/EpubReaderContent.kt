package app.storyarc.feature.epubreader

import android.view.WindowManager
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Annotation

/**
 * Everything drawn over the book: the chrome, its sheets and its dialogs.
 *
 * Moved out of [EpubReaderActivity.onCreate] unchanged. An extension on the activity, because
 * every control here reaches back into it: the navigator, the view model and the read-aloud
 * session are the activity's to hold.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun EpubReaderActivity.EpubReaderContent() {
    // Read, not fixed. `settings-and-about`'s appearance is the reader's and it
    // applies "across the whole app"; the Material You opt-out is
    // `native-experience`'s and belongs to the same choice. Both come from the
    // one read on `appearance`, which also carries why this one is the literal
    // choice rather than the resolved one.
    StoryArcTheme(
        appearance = appearance.chrome,
        useDynamicColor = appearance.useDynamicColor,
    ) {
        val progression by model.progression.collectAsStateWithLifecycle()
        val chapter by model.chapterTitle.collectAsStateWithLifecycle()
        val withinChapter by model.withinChapter.collectAsStateWithLifecycle()
        val failure by model.failure.collectAsStateWithLifecycle()
        val isVisible by model.isChromeVisible.collectAsStateWithLifecycle()
        val theme by model.theme.collectAsStateWithLifecycle()
        val values by model.values.collectAsStateWithLifecycle()
        val customPalette by model.customPalette.collectAsStateWithLifecycle()
        val transition by model.transition.collectAsStateWithLifecycle()
        val reduceMotion by model.reduceMotionFlow.collectAsStateWithLifecycle()
        val brightness by model.brightness.collectAsStateWithLifecycle()
        val contents by model.tableOfContents.collectAsStateWithLifecycle()
        val resource by model.currentResource.collectAsStateWithLifecycle()
        val bookmarks by model.bookmarks.collectAsStateWithLifecycle()
        val isPageBookmarked by model.isPageBookmarked.collectAsStateWithLifecycle()
        val matches by model.matches.collectAsStateWithLifecycle()
        val isSearching by model.isSearching.collectAsStateWithLifecycle()
        val note by model.note.collectAsStateWithLifecycle()
        val returnPoint by model.returnPoint.collectAsStateWithLifecycle()
        val canSpeak by canReadAloud.collectAsStateWithLifecycle()
        // The session belongs to `ReadAloudHost`, and this screen only observes
        // it. Scoped to this book, because a listener looking at one book while
        // another is being spoken must not get a transport in this chrome that
        // would pause a book they cannot see.
        val spoken by ReadAloudHost.session.collectAsStateWithLifecycle()
        val spokenBook by ReadAloudHost.book.collectAsStateWithLifecycle()
        val isThisBook = spokenBook?.id == bookId
        val annotations by model.annotations.collectAsStateWithLifecycle()
        val writing by writingNote.collectAsStateWithLifecycle()
        var editingNote by remember { mutableStateOf<Annotation?>(null) }
        // Either route into the editor: the selection bar's "Note", which
        // highlights first and lands here, or a row's own pencil. Named apart
        // from `note` above, which is the footnote a reader tapped.
        val writtenOn = writing ?: editingNote
        var isShowingTheme by remember { mutableStateOf(false) }
        var isShowingContents by remember { mutableStateOf(false) }

        // The other half of the two-control chrome: one button leaves the book
        // and this one is everything else. See `EpubMenuSheet.kt`.
        var isShowingMenu by remember { mutableStateOf(false) }
        var contentsTab by remember { mutableStateOf(ContentsTab.CONTENTS) }

        // Level two of the theme surface, which on this platform is a
        // destination rather than a second sheet. See `ThemeAxesScreen.kt`.
        var isCustomisingTheme by remember { mutableStateOf(false) }

        KeepOffHinge(container) // `native-experience`, Foldables. See `EpubHingeLayout.kt`.

        // `reading-themes`: reader-local. A window attribute rather than
        // the system setting, so it reverts when this screen goes away.
        LaunchedEffect(brightness) {
            window.attributes = window.attributes.apply {
                screenBrightness = brightness
                    ?: WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
            }
        }

        // `reading-themes`: visible immediately. Reduce Motion is a key too,
        // so turning it off mid-session applies at once, not on the next turn.
        LaunchedEffect(theme, values, transition, reduceMotion) { applyTheme(reduceMotion) }

        // `ebook-reader`: the reading theme follows the appearance "then and
        // there rather than at the next open", and only for the reader who
        // linked the two. The first run is a no-op, because the view model was
        // built with this same answer. What it catches is the device turning
        // dark while the book is open, which the effect above puts on the page.
        val linked = linkedReadingTheme(settings)
        LaunchedEffect(linked) { model.follow(linked) }

        // `page-transitions`: the reader picks a page turn *after* the book is
        // open, and Reduce Motion can turn a Slide into Fast fade's own turn, so
        // ownership follows `effective` and the swipe is armed, not one mode.
        val drawnTurn = model.transitions(reduceMotion).drawnTurn
        LaunchedEffect(drawnTurn) {
            interceptor.arm(drawnTurn, turns)
        }

        // `ebook-reader`: a footnote "opens in place". A bottom sheet is the
        // platform's own in-place, and it leaves the page it was tapped on
        // visible behind it.
        note?.let { text ->
            ModalBottomSheet(onDismissRequest = { model.dismissNote() }) {
                Text(
                    text = text,
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.padding(
                        horizontal = StoryArcSpace.gutter,
                        vertical = StoryArcSpace.lg,
                    ),
                )
            }
        }

        // A link out of the book names where it goes before it goes there.
        val going by leaving.collectAsStateWithLifecycle()
        going?.let { destination ->
            LeaveTheBookDialog(
                leaving = destination,
                onOpen = { leaveTheBook(destination) },
                onDismiss = { leaving.value = null },
            )
        }

        writtenOn?.let { mark ->
            NoteDialog(
                initial = mark.note,
                onSave = { text ->
                    model.annotate(mark, text)
                    writingNote.value = null
                    editingNote = null
                },
                onDismiss = {
                    writingNote.value = null
                    editingNote = null
                },
            )
        }

        if (isShowingContents) {
            ContentsBottomSheet(
                entries = contents.orEmpty(),
                currentResource = resource,
                bookmarks = bookmarks,
                matches = matches,
                isSearching = isSearching,
                onSearch = { model.search(it) },
                onGoToMatch = { match ->
                    go(match)
                    isShowingContents = false
                },
                annotations = annotations,
                onGoToAnnotation = { mark ->
                    go(mark)
                    isShowingContents = false
                },
                onEditAnnotation = { editingNote = it },
                onRemoveAnnotation = { model.removeAnnotation(it.id) },
                onExportAnnotations = { format -> share(annotations, format) },
                onGo = { link ->
                    go(link)
                    isShowingContents = false
                },
                onGoToBookmark = { bookmark ->
                    go(bookmark)
                    isShowingContents = false
                },
                onRemoveBookmark = { model.removeBookmark(it.id) },
                onDismiss = { isShowingContents = false },
                opensOn = contentsTab,
            )
        }

        if (isShowingTheme) {
            // Words from where the reader is, read once when the sheet opens —
            // re-reading the resource on every slider step would put a disk read
            // inside a drag.
            var excerpt by remember { mutableStateOf("") }
            LaunchedEffect(Unit) { excerpt = model.previewExcerpt() }

            ThemeSurface(
                theme = theme,
                values = values,
                customPalette = customPalette,
                onAdopt = { preset ->
                    model.adopt(preset)
                    // `ebook-reader`: "picking a preset applies it and leaves the
                    // surface, because that was the whole errand".
                    isShowingTheme = false
                },
                onAdoptColours = model::adoptColours,
                onCustomise = {
                    // Level one leaves as level two arrives: a destination is not
                    // a second sheet over the first, which is the whole point of
                    // it being a destination.
                    isShowingTheme = false
                    isCustomisingTheme = true
                },
                onDismiss = { isShowingTheme = false },
                chapter = chapter,
                excerpt = excerpt,
            )
        }

        if (isCustomisingTheme) {
            // Words from where the reader is, read once when the destination
            // opens. The position does not move while it is up, and re-reading
            // the resource on every slider step would put a disk read inside a
            // drag.
            var axesExcerpt by remember { mutableStateOf("") }
            LaunchedEffect(Unit) { axesExcerpt = model.previewExcerpt() }

            ThemeAxesScreen(
                theme = theme,
                values = values,
                brightness = brightness,
                onChange = model::change,
                onSet = model::set,
                onBrightness = model::setBrightness,
                onRestore = model::restoreTheme,
                onLeavePublisherStyles = model::leavePublisherStyles,
                onAdoptColours = model::adoptColours,
                onDiscardColours = model::discardCustomColours,
                choices = model.transitions(reduceMotion),
                onChooseTransition = model::choose,
                onClose = { isCustomisingTheme = false },
                chapter = chapter,
                excerpt = axesExcerpt,
            )
        }

        if (isShowingMenu) {
            EpubMenuSheet(
                facts = EpubMenuFacts(
                    chapter = chapter,
                    progression = progression,
                    withinChapter = withinChapter,
                    isPageBookmarked = isPageBookmarked,
                    isContentsReady = contents != null,
                    canReadAloud = canSpeak,
                    isReadingAloud = isThisBook && spoken.isActive,
                ),
                actions = EpubMenuActions(
                    onDismiss = { isShowingMenu = false },
                    onOpenContents = { panel ->
                        contentsTab = panel
                        isShowingMenu = false
                        isShowingContents = true
                    },
                    onToggleBookmark = { model.toggleBookmark() },
                    onOpenTheme = {
                        isShowingMenu = false
                        isShowingTheme = true
                    },
                    onStartReadAloud = {
                        isShowingMenu = false
                        startReadAloud()
                    },
                    onStopReadAloud = ReadAloudHost::end,
                ),
            )
        }

        EpubChrome(
            failure = failure,
            isVisible = isVisible,
            onClose = { finish() },
            onOpenMenu = { isShowingMenu = true },
        )

        // Not the chrome, and on screen on their own terms: `EpubReaderOverlays.kt`.
        EpubReaderOverlays(
            canReturn = returnPoint != null,
            onReturn = { model.takeReturnPoint()?.let { goToLocator(it, remember = false) } },
            isReadingAloud = isThisBook && spoken.isActive,
            isSpeaking = isThisBook && spoken.isPlaying,
            onToggleReadAloud = ReadAloudHost::toggle,
            onSkipSentence = ReadAloudHost::skip,
            onStopReadAloud = ReadAloudHost::end,
        )
        EpubEndOfBookOffer(this@EpubReaderContent, failure, progression) // Task 7.2.
    }
}
