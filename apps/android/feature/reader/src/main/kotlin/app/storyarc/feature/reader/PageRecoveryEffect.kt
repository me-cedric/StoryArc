package app.storyarc.feature.reader

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect

/**
 * Re-reads the page on screen while it has failed to arrive, for as long as the reader is
 * open. See [ReaderViewModel.watchForPageRecovery].
 *
 * `network-share`'s *Connection drops while reading*: "resume streaming at the current
 * page" after reconnecting -- nothing else on this page turns itself back into a read once
 * the first one has failed. A composable of its own, beside [ReaderScreen] rather than
 * inline in it, because that file is already at its line cap.
 */
@Composable
internal fun PageRecoveryEffect(viewModel: ReaderViewModel) {
    LaunchedEffect(viewModel) { viewModel.watchForPageRecovery() }
}
