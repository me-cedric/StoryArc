package app.storyarc.feature.settings

import android.text.format.Formatter
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import app.storyarc.core.model.SourceRemovalWording

/**
 * The sentence a removal confirmation shows, in words.
 *
 * [SourceRemovalWording] decides *which* sentence and with what figures; this is the one place
 * that turns the decision into a string, so the detail screen's dialog and the list's delete
 * button cannot describe the same source differently. Both used to say that no files are
 * deleted, which was false for any source holding a download.
 *
 * The bytes go through [Formatter.formatFileSize], the same helper as the *Downloaded* field
 * one screen up, so the dialog can never name a size spelled differently from the row the reader
 * read it on. The two counts are plurals resolved first, because a resource can inflect one
 * quantity and not two; the sentence then takes them as words. The titles plural is the one the
 * detail field and the list row already draw.
 */
@Composable
internal fun removalBody(wording: SourceRemovalWording): String = when (wording) {
    is SourceRemovalWording.TitlesOnly -> pluralStringResource(
        R.plurals.sources_remove_body,
        wording.titleCount,
        wording.titleCount,
    )
    is SourceRemovalWording.TitlesAndDownloads -> stringResource(
        R.string.sources_remove_body_with_downloads,
        pluralStringResource(R.plurals.sources_detail, wording.titleCount, wording.titleCount),
        pluralStringResource(
            R.plurals.sources_remove_downloads,
            wording.downloadCount,
            wording.downloadCount,
        ),
        Formatter.formatFileSize(LocalContext.current, wording.downloadedBytes),
    )
}
