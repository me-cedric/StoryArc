package app.storyarc.feature.settings

import android.content.ContentResolver
import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.FileDownload
import androidx.compose.material.icons.filled.FileUpload
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.persistence.LibraryImportOutcome
import app.storyarc.core.persistence.LibraryTransfer
import java.io.IOException
import java.io.InputStream
import java.time.LocalDate
import kotlinx.coroutines.launch

/**
 * The two rows that move a library to another device: export and import.
 *
 * `library-portability` tasks 2.5 and 3.1. Export opens its sheet, which ends in the system
 * document picker (`CreateDocument`). Import opens the system document picker (`OpenDocument`),
 * and what it returns opens the preview sheet. iOS's `LibraryTransferSection` offers the same
 * two rows.
 */
@Composable
internal fun LibraryTransferRows(
    transfer: LibraryTransfer,
    highlight: SettingsAnchor?,
    onImported: (LibraryImportOutcome) -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val exportState = remember { LibraryExportState() }
    val importState = remember { LibraryImportState() }
    var isExporting by remember { mutableStateOf(false) }
    var isImporting by remember { mutableStateOf(false) }

    // The picker names the file; what it returns is the one place the bytes are written.
    val createDocument = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("application/json"),
    ) { uri ->
        scope.launch {
            val written = exportState.deliver(
                uri?.let { picked -> { context.contentResolver.openOutputStream(picked, "wt") } },
            )
            if (written) {
                exportState.clearSecrets()
                isExporting = false
            }
        }
    }
    val openDocument = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        // Closing the picker is not a failure and says nothing.
        if (uri != null) {
            isImporting = true
            scope.launch { importState.load(UriFile(context.contentResolver, uri), transfer) }
        }
    }

    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xs)) {
        TransferRow(
            icon = Icons.Filled.FileUpload,
            label = stringResource(R.string.transfer_export),
            anchor = SettingsAnchor.EXPORT_LIBRARY,
            highlight = highlight,
        ) { isExporting = true }
        TransferRow(
            icon = Icons.Filled.FileDownload,
            label = stringResource(R.string.transfer_import),
            anchor = SettingsAnchor.IMPORT_LIBRARY,
            highlight = highlight,
        ) { openDocument.launch(IMPORT_TYPES) }
        Text(
            text = stringResource(R.string.transfer_section_footer),
            style = MaterialTheme.typography.bodySmall,
            color = LocalStoryArcPalette.current.textSecondary,
        )
    }

    if (isExporting) {
        LibraryExportSheet(
            state = exportState,
            onExport = {
                scope.launch {
                    exportState.prepare(transfer, BuildInfo.version)
                    if (exportState.prepared != null) {
                        createDocument.launch(ExportDestination.defaultName(LocalDate.now()))
                    }
                }
            },
            onDismiss = {
                exportState.clearSecrets()
                isExporting = false
            },
        )
    }
    if (isImporting) {
        LibraryImportSheet(
            state = importState,
            onImport = { skipping ->
                scope.launch { importState.confirm(transfer, skipping, onImported) }
            },
            onDismiss = {
                importState.reset()
                isImporting = false
            },
        )
    }
}

@Composable
private fun TransferRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    anchor: SettingsAnchor,
    highlight: SettingsAnchor?,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .settingsHighlight(anchor, highlight)
            .clickableRow(onClick),
        horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = null, tint = LocalStoryArcPalette.current.accent)
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            color = LocalStoryArcPalette.current.textPrimary,
        )
    }
}

/**
 * What the document picker may show: the JSON this app writes, and the types a provider gives a
 * `.json` file it does not know.
 */
private val IMPORT_TYPES = arrayOf("application/json", "text/plain", "application/octet-stream")

/** A picked file, read through the content resolver. */
internal class UriFile(private val resolver: ContentResolver, private val uri: Uri) : PickedFile {
    override fun size(): Long? = try {
        resolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getLong(0) else null
        }
    } catch (_: SecurityException) {
        null
    }

    override fun open(): InputStream? = try {
        resolver.openInputStream(uri)
    } catch (_: IOException) {
        null
    } catch (_: SecurityException) {
        null
    }
}
