package app.storyarc.feature.library

import androidx.annotation.StringRes
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Dns
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.RssFeed
import androidx.compose.material.icons.filled.Storage
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import app.storyarc.core.designsystem.theme.StoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcColor
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceKind

/**
 * Presentation for the domain's source types. Kept out of `core:model` so the
 * domain stays free of Compose — the same split iOS keeps between `StoryArcCore`
 * and `DesignSystem`.
 */
internal val SourceKind.icon: ImageVector
    get() = when (this) {
        SourceKind.LOCAL_FOLDER -> Icons.Filled.Folder
        SourceKind.NETWORK_SHARE -> Icons.Filled.Storage
        SourceKind.OPDS_CATALOG -> Icons.Filled.RssFeed
        SourceKind.KAVITA_SERVER -> Icons.Filled.Dns
    }

@get:StringRes
internal val SourceKind.titleRes: Int
    get() = when (this) {
        SourceKind.LOCAL_FOLDER -> R.string.source_kind_local_folder_title
        SourceKind.NETWORK_SHARE -> R.string.source_kind_network_share_title
        SourceKind.OPDS_CATALOG -> R.string.source_kind_opds_title
        SourceKind.KAVITA_SERVER -> R.string.source_kind_kavita_title
    }

@get:StringRes
internal val SourceKind.explanationRes: Int
    get() = when (this) {
        SourceKind.LOCAL_FOLDER -> R.string.source_kind_local_folder_explanation
        SourceKind.NETWORK_SHARE -> R.string.source_kind_network_share_explanation
        SourceKind.OPDS_CATALOG -> R.string.source_kind_opds_explanation
        SourceKind.KAVITA_SERVER -> R.string.source_kind_kavita_explanation
    }

@get:StringRes
internal val SourceConnectionState.statusRes: Int
    get() = when (this) {
        is SourceConnectionState.Connected -> R.string.source_state_connected
        is SourceConnectionState.Connecting -> R.string.source_state_connecting
        is SourceConnectionState.Unreachable -> R.string.source_state_unreachable
        is SourceConnectionState.Unauthorized -> R.string.source_state_unauthorized
    }

/**
 * Only `Unauthorized` is red. An unreachable source is grey, because `sources`
 * treats offline as a normal state rather than a failure.
 */
internal fun SourceConnectionState.indicatorColor(palette: StoryArcPalette): Color = when (this) {
    is SourceConnectionState.Connected -> StoryArcColor.Status.success
    is SourceConnectionState.Connecting -> palette.textTertiary
    is SourceConnectionState.Unreachable -> StoryArcColor.Status.offline
    is SourceConnectionState.Unauthorized -> StoryArcColor.Status.danger
}
