package app.storyarc.feature.library

import android.app.Application
import app.storyarc.core.format.CoverLoader
import java.io.File

/**
 * Where an audiobook's embedded cover is written once `LibraryScanner` reads it out.
 *
 * Task 16.9. Its own directory rather than [LibraryViewModel.coverCache]'s: that one is keyed
 * by publication id and pixel size and holds decoded bitmaps, where this holds one undecoded
 * original per source file — [CoverLoader] decodes it at whatever size is asked, the same as a
 * comic's own page.
 *
 * Its own file rather than another property in `LibraryViewModel.kt`: that file is already
 * past its line cap, and a cap already crossed may not grow further.
 *
 * **`filesDir`, not `cacheDir`, since task 1.1.** `StorageUsage.clearCache` empties the cache
 * directories, and the cached shelf written beside them is not cleared with them — so artwork
 * written to a cache directory left every audiobook in that shelf pointing at a file the
 * system had removed, and the cover came back only on the next full rescan.
 */
internal val LibraryViewModel.audiobookCoverCacheDir: File
    get() = File(getApplication<Application>().filesDir, "audio-covers")
