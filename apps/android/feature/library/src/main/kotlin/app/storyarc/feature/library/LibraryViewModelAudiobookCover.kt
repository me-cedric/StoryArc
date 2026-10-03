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
 */
internal val LibraryViewModel.audiobookCoverCacheDir: File
    get() = File(getApplication<Application>().cacheDir, "audio-covers")
