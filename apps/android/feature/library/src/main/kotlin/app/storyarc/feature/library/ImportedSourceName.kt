package app.storyarc.feature.library

import android.app.Application
import app.storyarc.core.persistence.ImportedCopies
import kotlinx.coroutines.flow.update

/*
 * What StoryArc's own source row is called, and in which language.
 *
 * Beside [LibraryViewModel] rather than inside it, because that file is already at the length
 * `scripts/line-cap.mjs` records for it. `SourceRetry.kt` and `SeriesStatusActions.kt` sit
 * here for the same reason.
 */

/**
 * The name of the imported-copies row, in the language the reader chose.
 *
 * `localization` asks a chosen language to reach the whole interface. A view model is not an
 * activity, and the per-app override is applied to an activity's own `attachBaseContext` --
 * so `getString` on the `Application` answers in the system's language, and a reader who set
 * StoryArc to French on a German device read "Auf diesem Gerät" in a French library.
 * [speakingReaderLanguage] reads the choice again on every call.
 */
internal fun LibraryViewModel.importedSourceName(): String =
    getApplication<Application>().speakingReaderLanguage()
        .getString(R.string.source_on_this_device)

/**
 * Keeps the stored row named [named], and says whether there was a row to keep.
 *
 * `Source.displayName` is written to disk by `SourceStore`, and this is the one name in the
 * registry that StoryArc writes rather than the reader or a server. Resolved once at creation
 * it would keep the language it was created in for ever, beside a library that had changed
 * language around it. Asked on every import and on every resume, which is when
 * `LibraryViewModel.registerImportedSource` runs.
 */
internal fun LibraryViewModel.keptImportedSourceNamed(named: String): Boolean {
    val existing = _registry.value[ImportedCopies.SOURCE_ID] ?: return false
    if (existing.displayName != named) {
        _registry.update { it.renaming(ImportedCopies.SOURCE_ID, named) }
        sourceStore?.save(_registry.value)
    }
    return true
}
