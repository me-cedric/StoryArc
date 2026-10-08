package app.storyarc.core.model

/**
 * One line of the import preview, as a value the screen words in four languages.
 *
 * `library-portability` / *The reader sees what will happen first*. The plan holds counts and
 * names; [previewLines] orders them and drops the empty ones, so the screen is a loop over the
 * list and a test can assert what the reader is told without drawing anything. iOS's
 * `ImportPreviewLine` is the same list in the same order.
 */
sealed interface ImportPreviewLine {
    /**
     * Hosts that gain a pinned certificate, and the source each arrived with. First, because it
     * is a change to what the app trusts and not a change to what the reader owns.
     */
    data class CertificatePins(val pins: List<CertificatePinNotice>) : ImportPreviewLine

    data class SourcesToAdd(val names: List<String>) : ImportPreviewLine

    data class SourcesNeedingSignIn(val names: List<String>) : ImportPreviewLine

    data class ShelvesToAdd(val names: List<String>) : ImportPreviewLine

    /** Shelves on both sides, with how many members the import adds to each. */
    data class ShelvesMerged(val shelves: List<ImportedShelf>) : ImportPreviewLine

    data class Progress(val add: Int, val merge: Int) : ImportPreviewLine

    data class Themes(val count: Int) : ImportPreviewLine

    data class Covers(val count: Int) : ImportPreviewLine

    data object SettingsChange : ImportPreviewLine

    /** The document holds nothing this device lacks. */
    data object NothingNew : ImportPreviewLine
}

/** What the reader is told, in the order they are told it. Never empty. */
fun LibraryImportPlan.previewLines(): List<ImportPreviewLine> {
    val lines = buildList {
        if (certificatePinsToAdd.isNotEmpty()) add(ImportPreviewLine.CertificatePins(certificatePinsToAdd))
        if (sourcesToAdd.isNotEmpty()) add(ImportPreviewLine.SourcesToAdd(sourcesToAdd))
        if (sourcesNeedingSignIn.isNotEmpty()) {
            add(ImportPreviewLine.SourcesNeedingSignIn(sourcesNeedingSignIn))
        }
        if (shelvesToAdd.isNotEmpty()) add(ImportPreviewLine.ShelvesToAdd(shelvesToAdd))
        if (shelvesToMerge.isNotEmpty()) add(ImportPreviewLine.ShelvesMerged(shelvesToMerge))
        if (progressToAdd + progressToMerge > 0) {
            add(ImportPreviewLine.Progress(progressToAdd, progressToMerge))
        }
        if (themeEntriesToAdd > 0) add(ImportPreviewLine.Themes(themeEntriesToAdd))
        if (coversToAdd > 0) add(ImportPreviewLine.Covers(coversToAdd))
        if (settingsWillChange) add(ImportPreviewLine.SettingsChange)
    }
    return lines.ifEmpty { listOf(ImportPreviewLine.NothingNew) }
}
