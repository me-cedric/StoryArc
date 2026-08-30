package app.storyarc.feature.library

import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.model.Source
import java.util.UUID

/**
 * Where the rail can send a reader.
 *
 * `native-experience`: a window with room for it "uses a multi-column layout with a
 * persistent sidebar, not a stretched phone layout". These are exactly the places a narrow
 * window reaches through the catalogue strip and the top bar's right-hand icons. The wide
 * window shows them all at once instead of keeping two of them behind chrome — nothing new
 * to learn, just nothing hidden.
 *
 * iOS's `SidebarDestination` holds the same three cases.
 */
sealed interface SidebarDestination {
    /** Everything already on the device. */
    data object Library : SidebarDestination

    /** One catalogue, server or share, browsed rather than scanned. */
    data class OneSource(val id: UUID) : SidebarDestination

    /** Collections and reading lists. */
    data object Shelves : SidebarDestination
}

/**
 * What a rail holds, in the order a reader meets it.
 *
 * A pure function of the registry, and the only place that order is decided, so the list
 * can be asserted without a device — which matters here, because there is no emulator in
 * this repository's loop. iOS's `SidebarDestination.all(for:)` returns the same three
 * groups in the same order.
 *
 * A local folder is deliberately absent: its publications were scanned into the grid, so a
 * row for it would lead back to the row above it.
 */
fun sidebarDestinations(sources: List<Source>): List<SidebarDestination> =
    buildList {
        add(SidebarDestination.Library)
        sources.filter { it.kind.isBrowsable }.forEach { add(SidebarDestination.OneSource(it.id)) }
        add(SidebarDestination.Shelves)
    }

/**
 * The persistent side navigation of a wide window.
 *
 * Material 3's own [NavigationRail] rather than a hand-built column: `native-experience`
 * says the platform's control is used wherever one exists, and this is the control — it
 * brings the selection indicator, the item spacing, the touch-target floor and the
 * expressive selection motion that a stack of buttons would each have to be given by hand.
 *
 * Settings sits at the foot and outside the selection, because it is a screen the reader
 * comes back from rather than a destination they stay in; a rail item that kept its
 * indicator after Settings closed would be claiming the library was somewhere else.
 */
@Composable
fun LibraryRail(
    sources: List<Source>,
    selected: SidebarDestination,
    onSelect: (SidebarDestination) -> Unit,
    onOpenSettings: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current
    NavigationRail(modifier = modifier, containerColor = palette.surfaceSunken) {
        sidebarDestinations(sources).forEach { destination ->
            when (destination) {
                is SidebarDestination.Library -> RailItem(
                    label = stringResource(R.string.library_title),
                    selected = selected == destination,
                    onClick = { onSelect(destination) },
                ) { Icon(Icons.AutoMirrored.Filled.MenuBook, contentDescription = null) }

                is SidebarDestination.OneSource -> {
                    // The registry is what the list was built from, so this lookup cannot
                    // miss — and if a source is removed between the two, the item is
                    // simply not drawn rather than crashing on an index.
                    val source = sources.firstOrNull { it.id == destination.id }
                    if (source != null) {
                        RailItem(
                            label = source.displayName,
                            selected = selected == destination,
                            onClick = { onSelect(destination) },
                        ) { Icon(source.kind.icon, contentDescription = null) }
                    }
                }

                is SidebarDestination.Shelves -> RailItem(
                    label = stringResource(R.string.shelves_title),
                    selected = selected == destination,
                    onClick = { onSelect(destination) },
                ) { Icon(Icons.Filled.Inventory2, contentDescription = null) }
            }
        }

        Spacer(Modifier.weight(1f))

        RailItem(
            label = stringResource(R.string.library_settings),
            selected = false,
            onClick = onOpenSettings,
        ) { Icon(Icons.Filled.Settings, contentDescription = null) }
    }
}

/**
 * One rail item, always labelled.
 *
 * `native-experience` requires that state is never carried by colour alone and that every
 * control has a meaningful label, so the text is not optional here even though Material
 * allows it to be — an icon-only rail is four grey glyphs to anyone who has not learnt
 * them.
 */
@Composable
private fun ColumnScope.RailItem(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
    icon: @Composable () -> Unit,
) {
    NavigationRailItem(
        selected = selected,
        onClick = onClick,
        icon = icon,
        label = { Text(text = label, maxLines = 1, overflow = TextOverflow.Ellipsis) },
        alwaysShowLabel = true,
    )
}
