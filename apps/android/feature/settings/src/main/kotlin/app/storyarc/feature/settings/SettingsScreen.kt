package app.storyarc.feature.settings

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
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
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
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
            onOpen = { open = it },
            onClose = onClose,
            modifier = modifier,
        )
        else -> GroupDetail(
            group = group,
            settings = settings,
            onChange = onChange,
            onBack = { open = null },
            modifier = modifier,
        )
    }
}

@Composable
private fun GroupList(
    settings: AppSettings,
    onOpen: (SettingsGroup) -> Unit,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
) {
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
            items(SettingsGroup.entries) { group ->
                ListItem(
                    supportingContent = { Text(group.summary(settings)) },
                    leadingContent = {
                        Icon(imageVector = group.icon, contentDescription = null)
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickableRow { onOpen(group) },
                ) {
                    Text(stringResource(group.titleRes))
                }
                HorizontalDivider()
            }
        }
    }
}

@Composable
private fun GroupDetail(
    group: SettingsGroup,
    settings: AppSettings,
    onChange: (AppSettings) -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
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
                .padding(StoryArcSpace.gutter),
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
        ) {
            when (group) {
                SettingsGroup.APPEARANCE -> AppearanceGroup(settings, onChange)
                SettingsGroup.READING -> ReadingGroup(settings, onChange)
                SettingsGroup.PRIVACY -> PrivacyGroup()
                SettingsGroup.ABOUT -> AboutGroup()
                // Named rather than hidden. A group whose rows arrive with a capability
                // that does not exist yet says so; hiding it leaves a reader hunting for
                // where sources live.
                SettingsGroup.SOURCES, SettingsGroup.DOWNLOADS, SettingsGroup.LANGUAGE ->
                    Text(
                        text = stringResource(group.pendingRes),
                        style = MaterialTheme.typography.bodyMedium,
                    )
            }
        }
    }
}
