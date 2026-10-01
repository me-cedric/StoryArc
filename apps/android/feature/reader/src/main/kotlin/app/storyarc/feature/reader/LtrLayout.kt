package app.storyarc.feature.reader

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.unit.LayoutDirection

/**
 * Pages read left-to-right on screen -- the "one step right" rule `local-library` states for
 * the next page -- whatever the interface language's own direction. The manifest sets
 * `supportsRtl="true"`, so an Arabic or Hebrew interface language mirrors a bare
 * `HorizontalPager` or `LazyRow` by default, paging a left-to-right comic backwards. A
 * right-to-left *publication* still reverses its own data, same as before; this only pins the
 * ambient layout the pager, the horizontal scroll and the thumbnail strip draw into.
 */
@Composable
internal fun Ltr(content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr, content = content)
}
