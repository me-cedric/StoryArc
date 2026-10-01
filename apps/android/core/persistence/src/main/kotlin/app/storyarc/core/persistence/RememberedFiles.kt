package app.storyarc.core.persistence

import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import java.util.UUID

/**
 * Single files another app handed over, remembered across launches.
 *
 * `local-library`: a publication handed over by another app is remembered "once and
 * unobtrusively". Android's own half of what `FolderBookmarks` already does for iOS --
 * except there is no bookmark blob to keep here: a persistable read grant already survives
 * a restart by itself (`ContentResolver.takePersistableUriPermission`), so the Uri's own
 * string is the whole of what this has to remember.
 *
 * 10.10: nothing kept one at all. `takePersistableUriPermission` was called only from the
 * three folder pickers, so the single publication a reader had just opened from another app
 * -- the one case Android's own scenario names as the exception -- never came back once the
 * app was closed.
 */
class RememberedFiles(private val preferences: SharedPreferences) {

    companion object {
        fun open(context: Context): RememberedFiles =
            RememberedFiles(context.getSharedPreferences("app.storyarc.rememberedFiles", Context.MODE_PRIVATE))

        /**
         * The source a remembered file's publication is filed under -- never `null`. The
         * managed folder's own walk always runs and always claims the `null` scope
         * ([FolderSource.folderSourceOf]), so a remembered file filed under it would be
         * read as "not seen by this walk" and removed by the very next scan.
         */
        val SOURCE_ID: UUID = UUID.fromString("9e0d1cef-0000-4000-8000-000000000002")

        private const val FILES = "files"
        private const val SEPARATOR = "\n"

        /** As many as iOS keeps -- see `FolderBookmarks.rememberedFileLimit`. */
        const val LIMIT = 20
    }

    /** Every remembered file, most recently remembered first. */
    fun all(): List<Uri> =
        preferences.getString(FILES, null)
            ?.split(SEPARATOR)
            ?.filter { it.isNotEmpty() }
            ?.map(Uri::parse)
            .orEmpty()

    /**
     * Remembers a file. Already remembered, it moves to the front rather than duplicating;
     * past [LIMIT], the file remembered longest ago falls off -- nothing in the app ever
     * asks the reader whether they meant to keep one, so the list has to end somewhere.
     */
    fun remember(uri: Uri) {
        val kept = (listOf(uri) + all().filterNot { it == uri }).take(LIMIT)
        write(kept)
    }

    fun forget(uri: Uri) {
        write(all().filterNot { it == uri })
    }

    private fun write(files: List<Uri>) {
        preferences.edit().putString(FILES, files.joinToString(SEPARATOR)).apply()
    }
}
