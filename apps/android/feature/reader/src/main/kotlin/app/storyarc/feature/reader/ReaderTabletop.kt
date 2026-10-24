package app.storyarc.feature.reader

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.isTraversalGroup
import androidx.compose.ui.semantics.paneTitle
import androidx.compose.ui.semantics.semantics
import app.storyarc.core.designsystem.navigation.TabletopSplit

/**
 * Tabletop posture (D3): the page on the upright half and the reader's controls on the flat half.
 *
 * `native-experience`, *Half-open on a table*. The flat half is a control surface, not a page, so
 * its controls do not hide while the posture lasts. A screen reader reads the page first and the
 * controls second, and says "Controls below" once, when the pane appears. At the largest text size
 * the controls scroll, so none is cut off.
 *
 * @param fold the fold in window pixels. The reader fills the window, so these are its own.
 */
@Composable
internal fun ReaderTabletop(
    fold: Rect,
    page: @Composable () -> Unit,
    controls: @Composable ColumnScope.() -> Unit,
) {
    val title = stringResource(R.string.reader_tabletop_controls)
    TabletopSplit(fold.top, fold.bottom, page = page) {
        // The sheet's own container colour: the strip and the slider are drawn for that surface.
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surfaceContainerLow) {
            Column(
                Modifier
                    .semantics {
                        paneTitle = title
                        isTraversalGroup = true
                    }
                    .verticalScroll(rememberScrollState()),
                content = controls,
            )
        }
    }
}
