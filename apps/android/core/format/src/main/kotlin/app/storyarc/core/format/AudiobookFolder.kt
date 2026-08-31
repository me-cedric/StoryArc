package app.storyarc.core.format

import java.io.File

/**
 * A directory of ordered audio files, read as one audiobook.
 *
 * `publication-formats`: "it is treated as a single audiobook whose parts play in that
 * order, **by the same ordering rule that makes a folder of images one comic**". So the
 * ordering is [PageOrdering.naturalCompare] rather than a second copy of it: the digit-run
 * rule that puts `part10` after `part2` has already produced one silent cross-platform
 * divergence in this codebase, and a second implementation of it is a second chance.
 *
 * This is the folder half of [FolderKind], which decides *whether* a directory is an
 * audiobook. Once it has, this says what the parts are.
 *
 * The counterpart to [ImageFolderArchive], and deliberately not a subtype of it: a
 * `ComicArchiveReading` promises pages and a cover, and an audiobook has neither.
 */
class AudiobookFolder private constructor(
    /** The directory this was read from, or null when the parts came from a list. */
    val root: File?,
    /** The parts, in playing order. */
    val parts: List<Part>,
    /**
     * Entries that looked like parts and hold nothing.
     *
     * `publication-formats`: a damaged audiobook plays "what it can and states how much it
     * could not". This is the count the player's own controls state. A resource fork or a
     * cover image is not counted — it was never a part.
     */
    val skippedPartCount: Int,
) {

    /** One audio file of the folder. */
    data class Part(
        /** Relative to [root], with `/` separators. */
        val path: String,
        /** What a listener is told they are in the middle of. See [partTitle]. */
        val title: String,
        val bytes: Long,
    )

    /** An entry the caller found, before this decides whether it is a part. */
    data class Candidate(val path: String, val bytes: Long)

    /** Whether the folder holds anything playable at all. */
    val isPlayable: Boolean get() = parts.isNotEmpty()

    companion object {

        /**
         * Reads a directory.
         *
         * Subdirectories are walked and ordered by full path, exactly as
         * [ImageFolderArchive] does — a book split into `disc1/` and `disc2/` is the
         * audiobook equivalent of chapters-as-folders, and it is how library services
         * actually export them.
         */
        fun open(directory: File): AudiobookFolder {
            if (!directory.isDirectory) throw ComicArchiveException.UnrecognisedContainer()
            val root = directory.canonicalFile

            val candidates = mutableListOf<Candidate>()
            for (file in root.walkTopDown()) {
                if (!file.isFile) continue
                // Symbolic links are not followed, for the reason [ImageFolderArchive]
                // gives: a folder is chosen by the user and is still untrusted input, and
                // a link pointing outside the root would read arbitrary files.
                if (file.canonicalFile != file.absoluteFile) continue
                candidates += Candidate(file.relativeTo(root).invariantSeparatorsPath, file.length())
            }
            return of(candidates, root)
        }

        /** The parts a list of entries makes. Split out so the rules assert without a disk. */
        fun of(candidates: List<Candidate>, root: File? = null): AudiobookFolder {
            val parts = mutableListOf<Part>()
            var skipped = 0

            for (candidate in candidates) {
                // The same exclusions pages already have, applied through the same call:
                // a resource fork is not evidence of an audiobook either.
                if (!PageOrdering.isCandidateEntry(candidate.path)) continue
                val name = candidate.path.substringAfterLast('/')
                val extension = name.substringAfterLast('.', "").lowercase()
                if (extension !in FolderKind.AUDIO_EXTENSIONS) continue

                // A zero-length file is a part that will never decode. Counted rather than
                // dropped, so the player can say "played 9, could not play 1".
                if (candidate.bytes == 0L) {
                    skipped++
                    continue
                }
                parts += Part(candidate.path, partTitle(name), candidate.bytes)
            }

            return AudiobookFolder(
                root = root,
                parts = parts.sortedWith { lhs, rhs ->
                    PageOrdering.naturalCompare(lhs.path, rhs.path)
                },
                skippedPartCount = skipped,
            )
        }

        /**
         * What a part is called, given only its file name.
         *
         * A **product decision**, recorded as one — no guideline says this. `design.md`:
         * "naming the chapter, not the file … `01 - track.mp3` is not what a listener is
         * in the middle of." A folder carries no chapter names, so the best available name
         * is the file's own with the two things that are not part of the name taken off:
         * the extension, and the ordering prefix a library service put there to make the
         * files sort.
         *
         * The prefix is dropped only when something is left. `03.mp3` keeps its `3`,
         * because a numbered row beats an empty one.
         */
        fun partTitle(fileName: String): String {
            val stem = fileName.substringBeforeLast('.', fileName).trim()
            val stripped = ORDERING_PREFIX.replace(stem, "").trim()
            val name = stripped.ifEmpty { stem }
            // `chapter two` from a file named that way reads as a title once it is on a
            // row of its own; `Chapter Two` from a file already capitalised is left alone.
            return if (name.none { it.isUpperCase() }) name.titlecasedWords() else name
        }

        /**
         * Leading digits and whatever separates them from the name.
         *
         * `01 - `, `02_`, `3.`, `004 `. Not a bare digit run with nothing after it — that
         * is handled by the caller keeping the stem when this leaves nothing.
         */
        private val ORDERING_PREFIX = Regex("""^\d+\s*[-_.)\]]*\s*""")

        private fun String.titlecasedWords(): String = split(' ').joinToString(" ") { word ->
            word.replaceFirstChar { it.uppercaseChar() }
        }
    }
}
