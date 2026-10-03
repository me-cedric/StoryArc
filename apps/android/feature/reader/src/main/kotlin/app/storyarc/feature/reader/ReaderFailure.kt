package app.storyarc.feature.reader

import androidx.annotation.StringRes

/**
 * The sentence the reader shows when a book does not open, and the words it fills in.
 *
 * A resource id and its arguments rather than a resolved `String`, so the screen resolves
 * the sentence in the reader's current language. The arguments are format names such as
 * `7-Zip`, never an exception's own text -- see `ReaderFailureSaysNothingInternalTest`.
 */
data class ReaderFailure(@StringRes val textRes: Int, val args: List<String> = emptyList())
