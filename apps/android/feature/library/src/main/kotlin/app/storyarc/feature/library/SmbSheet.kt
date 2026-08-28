package app.storyarc.feature.library

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Source

/**
 * Adding a network share.
 *
 * Two steps in one sheet: what to connect to, then which folder to read. `network-share`
 * asks for both -- the connection "validated before saving" with the specific failure named,
 * and the reader able to "browse the share's directory tree and pick the folder to use as
 * the library root".
 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun SmbSheet(
    connection: SmbConnection,
    onAdd: (Source) -> Unit,
    onDismiss: () -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    val step by connection.step.collectAsStateWithLifecycle()

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .verticalScroll(rememberScrollState())
                .padding(horizontal = StoryArcSpace.gutter)
                .padding(bottom = StoryArcSpace.xl),
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
        ) {
            Text(
                text = stringResource(R.string.smb_title),
                style = MaterialTheme.typography.headlineSmall,
                color = palette.textPrimary,
            )

            when (val current = step) {
                is SmbConnection.Step.Browsing -> Chooser(connection, current, onAdd, onDismiss)
                else -> Details(connection, current)
            }
        }
    }
}

@Composable
private fun ColumnScope.Details(connection: SmbConnection, step: SmbConnection.Step) {
    val palette = LocalStoryArcPalette.current
    val host by connection.host.collectAsStateWithLifecycle()
    val share by connection.share.collectAsStateWithLifecycle()
    val username by connection.username.collectAsStateWithLifecycle()
    val password by connection.password.collectAsStateWithLifecycle()

    OutlinedTextField(
        value = host,
        onValueChange = { connection.host.value = it },
        label = { Text(stringResource(R.string.smb_host_label)) },
        singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
        modifier = Modifier.fillMaxWidth(),
    )
    Text(
        text = stringResource(R.string.smb_host_hint),
        style = MaterialTheme.typography.bodySmall,
        color = palette.textSecondary,
    )

    OutlinedTextField(
        value = share,
        onValueChange = { connection.share.value = it },
        label = { Text(stringResource(R.string.smb_share_label)) },
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
    )

    OutlinedTextField(
        value = username,
        onValueChange = { connection.username.value = it },
        label = { Text(stringResource(R.string.smb_user_label)) },
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
    )
    Text(
        text = stringResource(R.string.smb_user_hint),
        style = MaterialTheme.typography.bodySmall,
        color = palette.textSecondary,
    )

    OutlinedTextField(
        value = password,
        onValueChange = { connection.password.value = it },
        label = { Text(stringResource(R.string.smb_password_label)) },
        singleLine = true,
        visualTransformation = PasswordVisualTransformation(),
        modifier = Modifier.fillMaxWidth(),
    )

    Button(
        onClick = { connection.connect() },
        enabled = connection.isReady() && step !is SmbConnection.Step.Connecting,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Text(stringResource(R.string.smb_connect))
    }

    when (step) {
        is SmbConnection.Step.Connecting ->
            CircularProgressIndicator(strokeWidth = 2.dp, modifier = Modifier.padding(2.dp))

        // `network-share` wants the specific failure, and the four the client separates are
        // four different sentences here.
        is SmbConnection.Step.Failed -> Text(
            text = step.message,
            style = MaterialTheme.typography.bodyMedium,
            color = palette.textPrimary,
        )

        else -> Unit
    }
}

@Composable
private fun ColumnScope.Chooser(
    connection: SmbConnection,
    step: SmbConnection.Step.Browsing,
    onAdd: (Source) -> Unit,
    onDismiss: () -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    val folders = step.entries.filter { it.isDirectory }

    // `network-share`: the detail screen states whether the connection is encrypted. Said
    // here too, because this is the moment a reader decides whether to trust it.
    Text(
        text = stringResource(
            if (step.identity.isEncrypted) R.string.smb_encrypted else R.string.smb_not_encrypted,
            step.identity.dialect,
        ),
        style = MaterialTheme.typography.bodySmall,
        color = palette.textSecondary,
    )

    Text(
        text = step.path.ifEmpty { stringResource(R.string.smb_root) },
        style = MaterialTheme.typography.titleMedium,
        color = palette.textPrimary,
    )

    LazyColumn(modifier = Modifier.heightIn(max = 280.dp)) {
        connection.parentOf(step.path)?.let { parent ->
            item(key = "up") {
                FolderRow(name = stringResource(R.string.catalogue_back), isUp = true) {
                    connection.enter(parent)
                }
            }
        }
        items(folders, key = { it.path }) { folder ->
            FolderRow(name = folder.name, isUp = false) { connection.enter(folder.path) }
        }
    }

    Button(
        onClick = {
            connection.source()?.let(onAdd)
            onDismiss()
        },
        modifier = Modifier.fillMaxWidth(),
    ) {
        Text(stringResource(R.string.smb_use_folder))
    }
}

@Composable
private fun FolderRow(name: String, isUp: Boolean, onOpen: () -> Unit) {
    val palette = LocalStoryArcPalette.current
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onOpen)
            .defaultMinSize(minHeight = 48.dp)
            .padding(vertical = StoryArcSpace.xs),
    ) {
        Icon(
            imageVector = if (isUp) Icons.AutoMirrored.Filled.ArrowBack else Icons.Filled.Folder,
            contentDescription = null,
            tint = palette.textSecondary,
        )
        Text(name, style = MaterialTheme.typography.bodyLarge, color = palette.textPrimary)
    }
}
