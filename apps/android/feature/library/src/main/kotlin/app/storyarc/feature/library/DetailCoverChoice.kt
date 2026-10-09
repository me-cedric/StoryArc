package app.storyarc.feature.library

import android.app.Application
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import app.storyarc.core.designsystem.control.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import app.storyarc.core.designsystem.control.MIN_TOUCH_TARGET
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.format.CoverArtwork
import app.storyarc.core.model.Publication
import java.io.ByteArrayOutputStream
import java.io.InputStream
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * What a publication page can offer about the picture in its hero.
 *
 * Tasks 2.2, 2.3 and 2.4 of `cover-for-every-publication`, as one value rather than four
 * parameters, so [DetailHero] and the six tests that compose it are not rewritten each time
 * this grows a control. [unavailable] is what a test composes and what a pane with no view
 * model behind it draws: exactly the hero that was there before this change.
 */
internal data class CoverChoice(
    /** Whether the reader has chosen this publication's cover themselves. */
    val hasChosen: Boolean = false,
    /**
     * Whether moving the publication would lose that choice.
     *
     * `cover-art`'s *A publication with no digest*. Said on the page rather than nowhere,
     * because a silent loss would be worse than a stated limit.
     */
    val isTiedToPath: Boolean = false,
    /** Opens the system photo picker, or null where this page cannot offer one. */
    val onChoose: (() -> Unit)? = null,
    /** Removes the chosen cover, or null where there is none to remove. */
    val onRemove: (() -> Unit)? = null,
    /** Whether the last picture the reader picked could not be used. */
    val isUnreadable: Boolean = false,
    /**
     * The ways of finding a cover this page offers, or null where it offers none.
     *
     * Task 6.2. A test that composes the hero without a view model leaves it null and draws
     * exactly the controls that were there before.
     */
    val finder: CoverFinder? = null,
) {
    internal companion object {
        /** A page that offers nothing: the hero exactly as it was before task 2.3. */
        val unavailable = CoverChoice()
    }
}

/**
 * The page's own cover choice, wired to the system photo picker.
 *
 * **`PickVisualMedia` and nothing else.** Android's photo picker runs in the system's own
 * process and returns one `Uri` the app is granted for that read alone — so there is no
 * `READ_MEDIA_IMAGES` permission to ask for, and `design.md`'s rule about not asking for what
 * you do not need is kept by the platform rather than by us. A document picker or a media
 * permission would both put a prompt in front of a reader who only wants to set a picture, and
 * `design.md` records that decision at length. iOS's `PhotosPicker` is the same bargain.
 */
@Composable
internal fun rememberCoverChoice(
    viewModel: LibraryViewModel,
    publication: Publication,
): CoverChoice {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var hasChosen by remember(publication.id) { mutableStateOf(false) }
    var isUnreadable by remember(publication.id) { mutableStateOf(false) }
    var isFinding by remember(publication.id) { mutableStateOf(false) }
    val isTiedToPath = remember(publication.id) { viewModel.chosenCoverIsTiedToPath(publication) }

    LaunchedEffect(publication.id) { hasChosen = viewModel.hasChosenCover(publication) }

    val picker = rememberLauncherForActivityResult(
        ActivityResultContracts.PickVisualMedia(),
    ) { picked ->
        val uri = picked ?: return@rememberLauncherForActivityResult
        scope.launch {
            // The bytes, and nothing else this app ever learns about the reader's gallery:
            // no album, no media id kept, no second picture. Nothing is fetched and nothing
            // is sent.
            val bytes = withContext(Dispatchers.IO) {
                runCatching {
                    context.contentResolver.openInputStream(uri)
                        ?.use { it.readAtMost(CoverArtwork.MAX_BYTES) }
                }.getOrNull()
            }
            val stored = bytes != null && viewModel.setCover(bytes, publication)
            hasChosen = stored
            isUnreadable = !stored
        }
    }

    // Read when the page opens, so the reader who turns the lookup on and comes back is offered
    // the search. The switch is the one input; the offer is [CoverFinderOffer]'s answer.
    val offer = remember(publication.id) {
        CoverFinderOffer.of(CoverLookup.lookUpIsOn(context.applicationContext as Application))
    }
    if (isFinding) {
        CoverFinderSheet(
            publication = publication,
            store = { viewModel.setCover(it, publication) },
            onDone = { stored ->
                isFinding = false
                hasChosen = hasChosen || stored
                isUnreadable = !stored
            },
            onDismiss = { isFinding = false },
        )
    }

    return CoverChoice(
        finder = CoverFinder(
            offer = offer,
            title = publication.displayTitle,
            author = publication.authors.firstOrNull(),
            onFind = { isFinding = true },
            // A browser may be missing on a device that has none. The row says what it does
            // and nothing here can improve on a tap that finds nobody to open it.
            onOpenWeb = { intent -> runCatching { context.startActivity(intent) } },
        ),
        hasChosen = hasChosen,
        isTiedToPath = isTiedToPath,
        onChoose = {
            picker.launch(
                PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly),
            )
        },
        onRemove = if (hasChosen) {
            {
                scope.launch {
                    viewModel.removeChosenCover(publication)
                    hasChosen = false
                }
            }
        } else {
            null
        },
        isUnreadable = isUnreadable,
    )
}

/**
 * What the cover's own menu cannot carry: the visible offer on an empty well, and two captions.
 *
 * Every action is a row of the menu [CoverActionsHost] draws on the cover. An empty well is
 * already the way in, but a well that is silently tappable is a well nobody taps, so a
 * coverless page also says "Add a cover" in words, and that label opens the same menu
 * (`cover-art`, *The cover's actions are one menu*). Nothing at all on a page that offers no
 * choice, which is what keeps a test's hero the hero it was.
 */
@Composable
internal fun CoverChoiceControls(
    choice: CoverChoice,
    hasCover: Boolean,
    modifier: Modifier = Modifier,
    /**
     * The page's own accent, or null where the cover gave none.
     *
     * These controls sit **inside** the hero's wash, and the wash is taken from the cover --
     * so once a reader has chosen a strongly coloured picture, a button drawn in the theme's
     * own primary is that colour on itself and disappears. `android-chosen-cover-light-
     * largest.png` caught exactly that before this parameter existed.
     * [DetailAccent.accent] is the one colour this page guarantees clears the 3:1 floor
     * against that wash, which is why it is the one used here.
     */
    accent: DetailAccent? = null,
    /** Opens the cover's menu, for the "Add a cover" label. */
    onOpenMenu: () -> Unit = {},
) {
    if (choice.onChoose == null) return
    val palette = LocalStoryArcPalette.current
    val content = accent?.accent ?: palette.accentText
    Column(
        modifier = modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        if (!hasCover) {
            TextButton(
                onClick = onOpenMenu,
                modifier = Modifier.heightIn(min = MIN_TOUCH_TARGET),
                colors = ButtonDefaults.textButtonColors(contentColor = content),
            ) {
                Text(text = stringResource(R.string.cover_add))
            }
        }
        if (choice.hasChosen && choice.isTiedToPath) {
            Text(
                text = stringResource(R.string.cover_tied_to_path),
                style = MaterialTheme.typography.labelSmall,
                color = if (accent == null) palette.textTertiary else content,
                textAlign = TextAlign.Center,
            )
        }
        if (choice.isUnreadable) {
            Text(
                text = stringResource(R.string.cover_unreadable),
                style = MaterialTheme.typography.labelSmall,
                color = if (accent == null) palette.textSecondary else content,
                textAlign = TextAlign.Center,
            )
        }
    }
}

/**
 * The stream's bytes, or null when it holds more than [limit]. A picked file is untrusted
 * input, and `readBytes` would hold a file of any size whole before anything could refuse it.
 */
internal fun InputStream.readAtMost(limit: Int): ByteArray? {
    val out = ByteArrayOutputStream()
    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
    while (true) {
        val read = read(buffer)
        if (read < 0) return out.toByteArray()
        if (out.size() + read > limit) return null
        out.write(buffer, 0, read)
    }
}
