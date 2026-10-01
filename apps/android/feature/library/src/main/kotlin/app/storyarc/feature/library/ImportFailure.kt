package app.storyarc.feature.library

/**
 * Why an import did not happen, and what the reader can be told about it.
 *
 * 10.8: a refused format used to be dropped -- `importFile` read `getOrNull()` and kept only
 * the file's name, so the dialog never said what the file was detected as, and
 * `library_import_failed`'s own sentence listed CBZ, CBR, CBT, EPUB and PDF, which stopped
 * being the list the moment M4B joined it. [detected] carries
 * `ImportedCopies.ImportException.Unsupported`'s own format name, `null` only for
 * `ImportException.Unreadable`, where there is none to carry.
 */
data class ImportFailure(val name: String, val detected: String?)
