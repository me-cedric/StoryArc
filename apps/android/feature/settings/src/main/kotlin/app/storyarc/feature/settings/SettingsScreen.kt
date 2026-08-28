package app.storyarc.feature.settings

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.AppSettings
import app.storyarc.core.model.Download
import app.storyarc.core.model.DownloadLibrary
import app.storyarc.core.model.Source
import app.storyarc.core.persistence.ReaderPreferences

/**
 * Settings, as the seven groups `settings-and-about` names.
 *
 * The spec is specific about *why* they are groups: "so that a person can find one
 * without reading all of them", and each summary row "states its current value, so a
 * setting can be checked without entering the group". That second clause is the reason
 * [SettingsGroup] carries a summary at all — a list of seven words would satisfy the
 * first clause and none of the second.
 *
 * Two groups are deliberately thin. Sources belongs to the connectors and Downloads to
 * `offline-downloads`; neither exists yet, so both state what they will hold rather than
 * opening onto an empty screen. Saying "not yet" is better than a blank page, and much
 * better than hiding the group and leaving a reader to wonder where sources live.
 */
/**
 * @param settings held by the host, not by this screen.
 *
 *   `settings-and-about` requires an appearance to apply "immediately across the whole
 *   app without a restart", and *immediately* means while the reader is still looking at
 *   the picker. A screen that owned its own copy and handed it back on the way out
 *   satisfied "without a restart" and failed "immediately" — the theme changed one screen
 *   too late. Hoisting the state is the whole fix.
 */
@Composable
fun SettingsScreen(
    settings: AppSettings,
    onChange: (AppSettings) -> Unit,
    /** Where the reading *defaults* live. A different store, for the reason task 2.3 gives. */
    readerStore: ReaderPreferences,
    /** Returns everything this screen can set to its default, and nothing else. */
    onReset: () -> Unit,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
    /**
     * The configured sources. Handed in, because the registry belongs to the library and a
     * feature module never depends on another feature module.
     */
    sources: List<Source> = emptyList(),
    itemCount: (Source) -> Int = { 0 },
    onRemoveSource: (Source) -> Unit = {},
    onRenameSource: (Source, String) -> Unit = { _, _ -> },
    /**
     * What is on the device, and what it weighs. Handed in for the same reason the sources
     * are: the downloads belong to the library that fetched them.
     */
    downloads: DownloadLibrary = DownloadLibrary(),
    bytesOnDisk: Long = 0L,
    onRemoveDownload: (Download) -> Unit = {},
    /** Moves a queued download one place earlier or later. */
    onReorderDownload: (Download, Boolean) -> Unit = { _, _ -> },
) {
    var open by remember { mutableStateOf<SettingsGroup?>(null) }

    // Enabled only inside a group, so the system back goes *up one level* rather than
    // out of Settings. The host's own handler closes Settings, and the innermost enabled
    // handler wins — which is how one gesture means two things without either knowing
    // about the other.
    BackHandler(enabled = open != null) { open = null }

    when (val group = open) {
        null -> GroupList(
            settings = settings,
            summary = LibrarySummary(sources.size, bytesOnDisk),
            onOpen = { open = it },
            onReset = onReset,
            onClose = onClose,
            modifier = modifier,
        )
        else -> GroupDetail(
            group = group,
            settings = settings,
            onChange = onChange,
            readerStore = readerStore,
            onBack = { open = null },
            modifier = modifier,
            sources = sources,
            itemCount = itemCount,
            onRemoveSource = onRemoveSource,
            onRenameSource = onRenameSource,
            downloads = downloads,
            bytesOnDisk = bytesOnDisk,
            onRemoveDownload = onRemoveDownload,
            onReorderDownload = onReorderDownload,
        )
    }
}

@Composable
private fun GroupList(
    settings: AppSettings,
    summary: LibrarySummary,
    onOpen: (SettingsGroup) -> Unit,
    onReset: () -> Unit,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
) {
    // `settings-and-about` asks for search across settings, "listing each match with its
    // group path". With seven groups the search earns its place by matching a *setting*
    // rather than a group: someone looking for "volume" should not have to guess that it
    // lives under Reading.
    var query by remember { mutableStateOf("") }
    var confirmingReset by remember { mutableStateOf(false) }

    if (confirmingReset) {
        ResetDialog(
            onConfirm = {
                confirmingReset = false
                onReset()
            },
            onDismiss = { confirmingReset = false },
        )
    }

    Scaffold(
        modifier = modifier.fillMaxSize(),
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.settings_title)) },
                navigationIcon = {
                    IconButton(onClick = onClose) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.settings_close),
                        )
                    }
                },
            )
        },
    ) { padding ->
        LazyColumn(modifier = Modifier.padding(padding)) {
            item {
                OutlinedTextField(
                    value = query,
                    onValueChange = { query = it },
                    label = { Text(stringResource(R.string.settings_search)) },
                    singleLine = true,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(
                            horizontal = StoryArcSpace.gutter,
                            vertical = StoryArcSpace.sm,
                        ),
                )
            }

            val matches = SettingsGroup.search(query)
            if (matches.isEmpty()) {
                item {
                    Text(
                        text = stringResource(R.string.settings_search_empty, query),
                        style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.padding(StoryArcSpace.gutter),
                    )
                }
            }

            items(matches) { match ->
                ListItem(
                    // The group path, which is what makes a match actionable: a reader who
                    // searched "volume" needs to know it lives under Reading.
                    supportingContent = {
                        Text(
                            if (match.settingRes == null) {
                                match.group.summary(settings, summary)
                            } else {
                                stringResource(match.group.titleRes)
                            },
                        )
                    },
                    leadingContent = {
                        Icon(imageVector = match.group.icon, contentDescription = null)
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickableRow { onOpen(match.group) },
                ) {
                    Text(stringResource(match.settingRes ?: match.group.titleRes))
                }
                HorizontalDivider()
            }

            if (query.isBlank()) {
                item {
                    ListItem(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickableRow { confirmingReset = true },
                    ) {
                        Text(
                            text = stringResource(R.string.settings_reset),
                            color = MaterialTheme.colorScheme.error,
                        )
                    }
                }
            }
        }
    }
}

/**
 * The reset, confirmed and scoped out loud.
 *
 * `settings-and-about`: the app "confirms and states explicitly that sources, downloads,
 * and reading progress are not affected". Naming what survives is the whole job — a
 * confirmation that only says "are you sure" makes a reader guess at the blast radius.
 */
@Composable
private fun ResetDialog(onConfirm: () -> Unit, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.settings_reset)) },
        text = { Text(stringResource(R.string.settings_reset_body)) },
        confirmButton = {
            TextButton(onClick = onConfirm) {
                Text(
                    text = stringResource(R.string.settings_reset_confirm),
                    color = MaterialTheme.colorScheme.error,
                )
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.settings_cancel))
            }
        },
    )
}

@Composable
private fun GroupDetail(
    group: SettingsGroup,
    settings: AppSettings,
    onChange: (AppSettings) -> Unit,
    readerStore: ReaderPreferences,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    sources: List<Source>,
    itemCount: (Source) -> Int,
    onRemoveSource: (Source) -> Unit,
    onRenameSource: (Source, String) -> Unit,
    downloads: DownloadLibrary,
    bytesOnDisk: Long,
    onRemoveDownload: (Download) -> Unit,
    onReorderDownload: (Download, Boolean) -> Unit,
) {
    Scaffold(
        modifier = modifier.fillMaxSize(),
        topBar = {
            TopAppBar(
                title = { Text(stringResource(group.titleRes)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.settings_back),
                        )
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(StoryArcSpace.gutter),
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
        ) {
            when (group) {
                SettingsGroup.APPEARANCE -> AppearanceGroup(settings, onChange)
                SettingsGroup.LANGUAGE -> LanguageGroup(settings, onChange)
                SettingsGroup.READING -> ReadingGroup(settings, onChange, readerStore)
                SettingsGroup.PRIVACY -> PrivacyGroup()
                SettingsGroup.ABOUT -> AboutGroup()
                // Named rather than hidden. A group whose rows arrive with a capability
                // that does not exist yet says so; hiding it leaves a reader hunting for
                // where sources live.
                SettingsGroup.SOURCES -> SourcesGroup(sources, itemCount, onRemoveSource, onRenameSource)
                SettingsGroup.DOWNLOADS -> DownloadsGroup(
                    library = downloads,
                    bytesOnDisk = bytesOnDisk,
                    sourceName = { id -> sources.firstOrNull { it.id == id }?.displayName },
                    onRemove = onRemoveDownload,
                    onReorder = onReorderDownload,
                    settings = settings,
                    onChange = onChange,
                )
            }
        }
    }
}
