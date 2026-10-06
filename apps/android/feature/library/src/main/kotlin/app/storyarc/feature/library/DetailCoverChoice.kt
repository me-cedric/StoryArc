package app.storyarc.feature.library

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Publication
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
                    context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                }.getOrNull()
            }
            val stored = bytes != null && viewModel.setCover(bytes, publication)
            hasChosen = stored
            isUnreadable = !stored
        }
    }

    return CoverChoice(
        hasChosen = hasChosen,
        isTiedToPath = isTiedToPath,
        onChoose = {
            picker.launch(
                PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly),
            )
        },
        onRemove = if (hasChosen) {
            {
                viewModel.removeChosenCover(publication)
                hasChosen = false
            }
        } else {
            null
        },
        isUnreadable = isUnreadable,
    )
}

/**
 * The controls the hero's own artwork cannot carry.
 *
 * An empty well is already the way in — it *is* the button, per task 2.3 — but a well that is
 * silently tappable is a well nobody taps, so the same offer is made in words underneath.
 * "Change cover" where there is one to change, "Choose a cover" where there is not. Nothing at
 * all on a page that offers no choice, which is what keeps a test's hero the hero it was.
 */
@Composable
internal fun CoverChoiceControls(
    choice: CoverChoice,
    hasCover: Boolean,
    modifier: Modifier = Modifier,
) {
    if (choice.onChoose == null) return
    val palette = LocalStoryArcPalette.current
    Column(
        modifier = modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm)) {
            // Said in words as well as offered on the well itself. A well that is silently
            // tappable is a well that nobody taps: `design.md` rule 2 asks for a label beside
            // anything a reader has to notice, and the glyph alone says only "no artwork".
            TextButton(onClick = choice.onChoose) {
                Text(
                    text = stringResource(
                        if (hasCover) R.string.cover_change else R.string.cover_choose,
                    ),
                )
            }
            choice.onRemove?.let { remove ->
                TextButton(onClick = remove) {
                    Text(text = stringResource(R.string.cover_remove))
                }
            }
        }
        if (choice.hasChosen && choice.isTiedToPath) {
            Text(
                text = stringResource(R.string.cover_tied_to_path),
                style = MaterialTheme.typography.labelSmall,
                color = palette.textTertiary,
                textAlign = TextAlign.Center,
            )
        }
        if (choice.isUnreadable) {
            Text(
                text = stringResource(R.string.cover_unreadable),
                style = MaterialTheme.typography.labelSmall,
                color = palette.textSecondary,
                textAlign = TextAlign.Center,
            )
        }
    }
}
