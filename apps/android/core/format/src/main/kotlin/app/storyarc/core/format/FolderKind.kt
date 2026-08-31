package app.storyarc.core.format

/**
 * What a folder of files is, decided from the names of its entries.
 *
 * `publication-formats` lists a plain folder of ordered images as a publication, and a
 * folder of ordered audio as one too. So a folder has to be asked which it is, and for
 * a folder holding both the spec gives a majority rule and requires the app to state
 * which it chose — hence an answer returned to a caller rather than a decision taken
 * quietly inside a reader.
 *
 * **This one reads extensions, and every other detection in this layer does not.** That
 * is a real inconsistency and it is deliberate. The unit being detected here is the
 * *folder*, and its only cheap evidence is its entries' names: sniffing the head of
 * every entry would be one read per file, which for a 500-page comic folder is 500 reads
 * to answer a question the caller asks before opening anything. The parts themselves are
 * still sniffed from their bytes when they are opened, so a mislabelled part is caught
 * then — by [FormatSniffer], where the contents really are the fact.
 */
enum class FolderKind {
    /** A folder of ordered images. */
    COMIC,

    /** A folder of ordered audio, played as one publication. */
    AUDIOBOOK,
    ;

    companion object {
        /**
         * Audio extensions a folder's parts may carry.
         *
         * Kept beside [PageOrdering.IMAGE_EXTENSIONS] in spirit: the two sets are what
         * the majority below counts, and a format in neither is not evidence either way.
         */
        val AUDIO_EXTENSIONS = setOf(
            "mp3", "m4a", "m4b", "aac", "flac", "opus", "ogg", "oga", "wav", "aiff", "aif",
        )

        /**
         * The kind a folder's entries make it, or `null` when nothing in it is either.
         *
         * `null` rather than a default, because a caller has to be able to say "this
         * folder holds no publication" instead of opening an empty one.
         */
        fun of(entryNames: Iterable<String>): FolderKind? {
            var images = 0
            var audio = 0
            for (name in entryNames) {
                // The same exclusions pages already have — resource forks, dotfiles and
                // metadata are not evidence of anything.
                if (!PageOrdering.isCandidateEntry(name)) continue
                val ext = name.substringAfterLast('.', "").lowercase()
                if (ext in PageOrdering.IMAGE_EXTENSIONS) images++
                if (ext in AUDIO_EXTENSIONS) audio++
            }
            if (images == 0 && audio == 0) return null
            // A tie is a comic. A **product decision**, not a rule from anywhere: a
            // folder of images is what StoryArc has always made of a folder, and a tie
            // is the one case where deciding otherwise would change existing behaviour
            // for no reason the spec states.
            return if (audio > images) AUDIOBOOK else COMIC
        }
    }
}
