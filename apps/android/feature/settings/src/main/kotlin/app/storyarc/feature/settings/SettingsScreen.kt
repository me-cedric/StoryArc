package app.storyarc.feature.settings

import app.storyarc.core.designsystem.back.PredictiveBack
import app.storyarc.core.designsystem.back.PredictiveBackHost
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
import app.storyarc.core.model.DownloadLibrary
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceAction
import app.storyarc.core.model.SourceDiagnosis
import app.storyarc.core.persistence.ImportedCopies
import app.storyarc.core.persistence.ReaderPreferences
import java.util.UUID

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
     * Whether to open straight at Downloads, because something outside asked for it.
     *
     * `native-experience`'s home-screen menu offers Downloads directly, and this screen's
     * navigation is its own state -- so the host says where to land rather than reaching
     * in. iOS's `SettingsView` takes the same flag, in the same place.
     */
    opensAtDownloads: Boolean = false,
    /**
     * The configured sources. Handed in, because the registry belongs to the library and a
     * feature module never depends on another feature module.
     */
    sources: List<Source> = emptyList(),
    itemCount: (Source) -> Int = { 0 },
    onRemoveSource: (Source) -> Unit = {},
    onRenameSource: (Source, String) -> Unit = { _, _ -> },
    /** Moves a source one place, up or down. `sources`: the order persists and decides precedence. */
    onReorderSource: (Source, Boolean) -> Unit = { _, _ -> },
    /**
     * Runs one of the five actions a source's detail screen offers. `sources` names all
     * five; four of them had nowhere to be pressed.
     */
    onSourceAction: (Source, SourceAction) -> Unit = { _, _ -> },
    /**
     * What is on the device, and what it weighs. Handed in for the same reason the sources
     * are: the downloads belong to the library that fetched them.
     */
    downloads: DownloadLibrary = DownloadLibrary(),
    bytesOnDisk: Long = 0L,
    /**
     * Removes every download at once, which is what the Privacy screen's "clear downloads"
     * means. The only download action left on this screen: removing one at a time belongs to
     * the Downloads destination now, and clearing is not that in a loop — the host does it in
     * one write, so a reader is never left with half a library gone.
     */
    onClearDownloads: () -> Unit = {},
) {
    // The match rather than the group, because a search result that named a *setting* has
    // to survive the navigation: the group is where to go, the anchor is what to point at
    // once there.
    var open by remember {
        mutableStateOf(SettingMatch.of(SettingsGroup.DOWNLOADS).takeIf { opensAtDownloads })
    }

    // Which source is being diagnosed, when one is. A third level rather than a dialog:
    // `sources` calls it a screen, it carries five fields and five actions, and the two
    // destructive ones need a confirmation of their own on top.
    var openSource by remember { mutableStateOf<UUID?>(null) }
    val diagnosed = sources.firstOrNull { it.id == openSource }

    // `native-experience` asks for predictive back on Android, and the manifest opt-in is
    // only the half the system can do for itself: it draws the way out of the *app*. These
    // three levels are the app's own state, so the preview of one of them leaving is the
    // app's own to draw -- and until this host existed above them, the two handlers below
    // fired their callbacks and animated nothing, exactly as `PredictiveBack`'s KDoc warns.
    //
    // Around the whole of Settings rather than around each level, because that is the shape
    // the host is written for: exactly one of the three screens below is composed at a time,
    // so exactly one handler is ever enabled and one transform can never be applied twice.
    PredictiveBackHost {
        // Enabled only inside a group, so the system back goes *up one level* rather than
        // out of Settings. The app shell's own handler closes Settings, and the innermost
        // enabled handler wins — which is how one gesture means three things without any of
        // them knowing about the others: a source's screen goes back to the group, the
        // group goes back to the list, and the list closes Settings.
        PredictiveBack(enabled = open != null) { open = null }
        PredictiveBack(enabled = openSource != null) { openSource = null }

        // A `when` rather than the early return this used to take: everything the gesture
        // can leave has to be composed *inside* the host, or the transform has nothing to
        // apply itself to.
        if (diagnosed != null) {
            SourceDetailScreen(
                source = diagnosed,
                diagnosis = SourceDiagnosis.of(
                    diagnosed,
                    itemCount = itemCount(diagnosed),
                    downloads = downloads.downloads,
                    // "On this device" is the app's own imported copies, not a source the
                    // reader added, so it is not one they can remove. The same exception the
                    // list makes, asked once so the two cannot disagree.
                    isRemovable = diagnosed.id != ImportedCopies.SOURCE_ID,
                ),
                onAction = { onSourceAction(diagnosed, it) },
                onBack = { openSource = null },
                modifier = modifier,
            )
        } else {
            when (val match = open) {
                null -> GroupList(
                    settings = settings,
                    summary = LibrarySummary(sources.size, bytesOnDisk),
                    onOpen = { open = it },
                    onReset = onReset,
                    onClose = onClose,
                    modifier = modifier,
                )
                else -> GroupDetail(
                    group = match.group,
                    highlight = match.anchor,
                    settings = settings,
                    onChange = onChange,
                    readerStore = readerStore,
                    onBack = { open = null },
                    modifier = modifier,
                    sources = sources,
                    itemCount = itemCount,
                    onRemoveSource = onRemoveSource,
                    onRenameSource = onRenameSource,
                    onReorderSource = onReorderSource,
                    onOpenSource = { openSource = it.id },
                    downloads = downloads,
                    bytesOnDisk = bytesOnDisk,
                    onClearDownloads = onClearDownloads,
                )
            }
        }
    }
}

@Composable
private fun GroupList(
    settings: AppSettings,
    summary: LibrarySummary,
    onOpen: (SettingMatch) -> Unit,
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
                            if (match.anchor == null) {
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
                        .clickableRow { onOpen(match) },
                ) {
                    Text(stringResource(match.anchor?.titleRes ?: match.group.titleRes))
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
    /**
     * The row a search result pointed at, if the reader arrived through one.
     *
     * Travels all the way down rather than being resolved here, because the row is the only
     * thing that knows where it is — a screen cannot tint what it does not lay out.
     */
    highlight: SettingsAnchor?,
    settings: AppSettings,
    onChange: (AppSettings) -> Unit,
    readerStore: ReaderPreferences,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    sources: List<Source>,
    itemCount: (Source) -> Int,
    onRemoveSource: (Source) -> Unit,
    onRenameSource: (Source, String) -> Unit,
    onReorderSource: (Source, Boolean) -> Unit,
    onOpenSource: (Source) -> Unit,
    downloads: DownloadLibrary,
    bytesOnDisk: Long,
    onClearDownloads: () -> Unit,
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
                SettingsGroup.APPEARANCE -> AppearanceGroup(settings, onChange, highlight = highlight)
                SettingsGroup.LANGUAGE -> LanguageGroup(settings, onChange)
                SettingsGroup.READING ->
                    ReadingGroup(settings, onChange, readerStore, highlight = highlight)
                SettingsGroup.PRIVACY -> PrivacyGroup(
                    downloadedBytes = bytesOnDisk,
                    onClearDownloads = onClearDownloads,
                    highlight = highlight,
                )
                SettingsGroup.ABOUT -> AboutGroup()
                // Named rather than hidden. A group whose rows arrive with a capability
                // that does not exist yet says so; hiding it leaves a reader hunting for
                // where sources live.
                SettingsGroup.SOURCES ->
                    SourcesGroup(
                        sources = sources,
                        itemCount = itemCount,
                        onRemove = onRemoveSource,
                        onRename = onRenameSource,
                        onOpen = onOpenSource,
                        onReorder = onReorderSource,
                    )
                SettingsGroup.DOWNLOADS -> DownloadsGroup(
                    bytesOnDisk = bytesOnDisk,
                    settings = settings,
                    onChange = onChange,
                    highlight = highlight,
                )
            }
        }
    }
}
