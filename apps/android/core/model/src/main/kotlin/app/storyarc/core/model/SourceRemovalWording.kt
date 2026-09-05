package app.storyarc.core.model

/**
 * Which sentence a removal confirmation shows, and the figures it carries.
 *
 * `sources`, *Removing a source*: the app "states how many downloaded files and how much disk
 * space will be freed before asking for confirmation", and on confirmation removes the source
 * "and its downloads". The sentence the reader confirmed against said the opposite — *"No files
 * on your device are deleted, and nothing was downloaded"* — which is true for a source with no
 * downloads and a false promise for one with 400 MB of them, while both apps deleted the files
 * anyway: `SettingsHost`'s `REMOVE` and iOS's `StoryArcAppActions.removeSource` call
 * `removeDownloads` before the model forgets the source. The space freed was stated nowhere
 * before the tap.
 *
 * One rule for both dialogs on both platforms, with no words in it. The wording lives in the
 * feature that draws it, in four languages; this is which of the two sentences to draw and what
 * to put in the holes — the same split [SourceFailure] makes. Decided by the count of finished
 * downloads rather than by their bytes: a finished download that weighs nothing is still a file
 * the removal deletes, and a sentence saying nothing is deleted would be wrong about it. iOS's
 * `SourceRemovalWording` answers the same way, and its test mirrors this one's.
 *
 * Two states and not three sentences, and each state is one sentence, because iOS's
 * confirmation at the largest accessibility text size shows about seven short lines and does not
 * scroll — photographed on 2026-09-05. Android's dialog scrolls, and mirrors the rule anyway:
 * the two apps share rules, never UI (ADR-0001), and a rule that differed by platform would let
 * one reader be promised something the other is not.
 */
sealed interface SourceRemovalWording {
    /**
     * Nothing of this source is on disk. The removal frees no bytes, so the sentence names only
     * what leaves the library.
     */
    data class TitlesOnly(val titleCount: Int) : SourceRemovalWording

    /**
     * Some of it is. The sentence names the files the removal deletes and the space they take,
     * figures first, so that a frame that runs out of room loses words rather than numbers.
     */
    data class TitlesAndDownloads(
        val titleCount: Int,
        val downloadCount: Int,
        val downloadedBytes: Long,
    ) : SourceRemovalWording

    companion object {
        /**
         * The sentence for a source that holds [titleCount] publications, [downloadCount] of
         * them finished on disk, weighing [downloadedBytes] between them.
         */
        fun of(titleCount: Int, downloadCount: Int, downloadedBytes: Long): SourceRemovalWording =
            if (downloadCount > 0) {
                TitlesAndDownloads(titleCount, downloadCount, downloadedBytes)
            } else {
                TitlesOnly(titleCount)
            }

        /**
         * The sentence for a source as its detail screen already knows it.
         *
         * [SourceDiagnosis] counts the finished downloads and their bytes for the *Downloaded*
         * field; taking them from there is what keeps the dialog from naming a figure the row
         * did not. The list's delete button has no detail screen open and asks the same question
         * the same way.
         */
        fun of(diagnosis: SourceDiagnosis): SourceRemovalWording =
            of(diagnosis.itemCount, diagnosis.downloadCount, diagnosis.downloadedBytes)
    }
}
