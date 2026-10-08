package app.storyarc.feature.library

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.format.CoverArtwork
import app.storyarc.core.format.CoverOverrideStore
import app.storyarc.core.kavita.KavitaClient
import app.storyarc.core.kavita.KavitaReadingList
import app.storyarc.core.kavita.uploadReadingListCover
import app.storyarc.core.model.CoverWriteSubject
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * What a Kavita reading list's own cover needs decided before it is drawn.
 *
 * Tasks 6.4 and 5.1 of `cover-for-every-publication`. Free of the screen so a test can state
 * both rules without a composition. iOS's `KavitaListCover` is its twin.
 */
internal object KavitaListCover {

    /**
     * A server list as the cover-override store names it, under the same kind of identity
     * [chapterPublication] gives a chapter, so the two cannot be filed under one key.
     *
     * Null when the source is not named by a UUID, which no registered source fails to be: a
     * list there has nowhere to keep a chosen cover, so none is offered.
     */
    fun publication(serverId: String, listId: Int): Publication? {
        val source = runCatching { UUID.fromString(serverId) }.getOrNull() ?: return null
        return Publication(
            identity = PublicationIdentity(
                serverIdentifier = PublicationIdentity.ServerIdentifier(source, "list:$listId"),
            ),
            format = PublicationFormat.CBZ,
            displayTitle = "",
            origin = MetadataOrigin.AUTHORITATIVE,
        )
    }

    /**
     * What the write-back button is asked about, or null where it is not placed at all.
     *
     * Two things must hold before the button exists. A cover has been chosen, because the
     * button's Send has nothing to send otherwise. And the server has said this list is in its
     * answer, because `ReadingList/lists` is the only place the `promoted` flag comes from:
     * a list the server did not list, or an answer that never arrived, proves no ownership.
     * Whether a promoted list is then refused is [app.storyarc.core.model.CoverWriteBack]'s
     * decision and nobody else's.
     */
    fun writeSubject(
        listId: Int,
        hasChosen: Boolean,
        lists: List<KavitaReadingList>?,
    ): CoverWriteSubject? {
        if (!hasChosen) return null
        val held = lists?.firstOrNull { it.id == listId } ?: return null
        return CoverWriteSubject.KavitaReadingList(listId, held.promoted)
    }

    /** Crops the picture to a cover's shape and files it. False is a picture that cannot be used. */
    suspend fun choose(
        overrides: CoverOverrideStore,
        list: Publication,
        picture: ByteArray,
    ): Boolean = withContext(Dispatchers.IO) {
        val shaped = CoverArtwork.coverShaped(picture) ?: return@withContext false
        overrides.store(shaped, list) != null
    }
}

/**
 * The list's own cover, and the one menu a reader changes it from.
 *
 * A picture of the reader's own choosing, kept on this device. Once one is chosen, and only
 * then, the reader may also send it to the server, where [rememberCoverWriteBack] confirms that
 * this changes the cover for everyone who can see the list.
 */
@Composable
internal fun KavitaListCoverControls(
    serverId: String,
    listId: Int,
    client: KavitaClient,
    overrides: CoverOverrideStore,
    modifier: Modifier = Modifier,
) {
    val list = remember(serverId, listId) { KavitaListCover.publication(serverId, listId) } ?: return
    val palette = LocalStoryArcPalette.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    var revision by remember(listId) { mutableIntStateOf(0) }
    var chosen by remember(listId) { mutableStateOf<Bitmap?>(null) }
    var unreadable by remember(listId) { mutableStateOf(false) }
    var lists by remember(listId) { mutableStateOf<List<KavitaReadingList>?>(null) }

    LaunchedEffect(list, revision) {
        chosen = withContext(Dispatchers.IO) {
            overrides.bytes(list)?.let { runCatching { BitmapFactory.decodeByteArray(it, 0, it.size) }.getOrNull() }
        }
    }
    LaunchedEffect(listId) { lists = runCatching { client.readingLists() }.getOrNull() }

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { picked ->
        val uri = picked ?: return@rememberLauncherForActivityResult
        scope.launch {
            val bytes = withContext(Dispatchers.IO) {
                runCatching {
                    context.contentResolver.openInputStream(uri)?.use { it.readAtMost(CoverArtwork.MAX_BYTES) }
                }.getOrNull()
            }
            val stored = bytes != null && KavitaListCover.choose(overrides, list, bytes)
            unreadable = !stored
            if (stored) revision += 1
        }
    }

    val send = rememberCoverWriteBack(
        subject = KavitaListCover.writeSubject(listId, hasChosen = chosen != null, lists = lists),
        image = { withContext(Dispatchers.IO) { overrides.bytes(list) } },
        send = { id, picture -> client.uploadReadingListCover(id, picture) },
    )
    val menu = CoverMenu(
        onChoose = {
            picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
        },
        onSend = send,
        onRemove = if (chosen == null) {
            null
        } else {
            {
                scope.launch {
                    withContext(Dispatchers.IO) { overrides.remove(list) }
                    revision += 1
                }
            }
        },
    )
    var menuOpen by remember(listId) { mutableStateOf(false) }

    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
        modifier = modifier.padding(bottom = StoryArcSpace.sm),
    ) {
        CoverActionsHost(menu, menuOpen, { menuOpen = it }, accent = null) {
            Surface(
                color = palette.surfaceRaised,
                shape = RoundedCornerShape(StoryArcRadius.sm),
                modifier = Modifier.height(COVER_HEIGHT).aspectRatio(2f / 3f),
            ) {
                chosen?.let {
                    Image(
                        bitmap = it.asImageBitmap(),
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxSize(),
                    )
                }
            }
        }
        Column {
            if (chosen == null) {
                TextButton(onClick = { menuOpen = true }) {
                    Text(stringResource(R.string.cover_add))
                }
            }
            if (unreadable) {
                Text(
                    text = stringResource(R.string.cover_unreadable),
                    style = MaterialTheme.typography.labelSmall,
                    color = palette.textSecondary,
                )
            }
        }
    }
}

/** The cover's height: a header's thumbnail, taller than a row's poster and no larger. */
private val COVER_HEIGHT = 88.dp
