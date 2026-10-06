package app.storyarc.core.format

import java.io.File

/**
 * A cover image that sits *beside* a publication rather than inside it.
 *
 * Task 1.2 of `cover-for-every-publication`, and the `cover-art` ladder's second rung: "the
 * file carries no artwork, and a `cover`, `folder` or `poster` image sits in the same folder,
 * or in an audiobook's own folder". It is the cheapest rung after the bytes themselves —
 * nothing is decoded to find it and nothing leaves the device — and it is what a folder ripped
 * from a CD or exported by a media server almost always already carries.
 *
 * [AudiobookCover.inFolder] asked the same question for audiobook folders alone, under six
 * hard-coded names. The names live here now so one rung answers for every format, and so
 * `poster` — which Jellyfin and Plex write and which the earlier list did not know — is found
 * by the shelf as well as by the player. iOS's `LooseCover.swift` is its twin, name for name
 * and order for order.
 */
object LooseCover {

    /**
     * The stems a loose cover is looked for under, in the order they are tried.
     *
     * `cover` first because it is what this app's own export writes, then `folder`, which is
     * the Windows Media and Kodi convention, then `poster`, which is Jellyfin's and Plex's.
     */
    val stems = listOf("cover", "folder", "poster")

    /**
     * The extensions each stem is tried with, in the order they are tried.
     *
     * Every one of these is a format [PageDecoder] already decodes, so a name found here can
     * always be drawn. A `.gif` or a `.bmp` beside a book is far likelier to be an
     * illustration than a cover, which is why the list stops where it does.
     */
    val fileExtensions = listOf("jpg", "jpeg", "png", "webp", "heic")

    /**
     * Every name tried, stem by stem, extension within stem.
     *
     * Stem outermost on purpose: a folder holding both `cover.png` and `folder.jpg` means the
     * first, and a reader who wrote `cover.png` should not be answered with the picture their
     * media server left behind.
     */
    val fileNames: List<String> = stems.flatMap { stem -> fileExtensions.map { "$stem.$it" } }

    /** A loose cover inside [folder], or null when it holds none. */
    fun inFolder(folder: File): File? =
        fileNames.map { File(folder, it) }.firstOrNull { it.isFile }

    /**
     * A loose cover for the publication stored at [file], whether that is a file or a folder.
     *
     * A folder is searched; a file's own directory is searched. The two cases are one rung
     * rather than two because the reader does not experience them as different: the picture is
     * "the one next to the book", and whether the book is a file or a folder of files is the
     * container's business.
     */
    fun beside(file: File): File? = when {
        file.isDirectory -> inFolder(file)
        file.isFile -> file.parentFile?.let(::inFolder)
        else -> null
    }

    /**
     * The best loose-cover name among [names], or null when none of them is one.
     *
     * The one reader for a Storage Access Framework child. A document tree has no paths to
     * build a [File] out of — a child is reached by its own document id — so the scanner lists
     * the folder once and asks this which of the names it saw is the cover. Order is
     * [fileNames]' order, so SAF and the filesystem answer the same folder the same way.
     */
    fun named(names: Iterable<String>): String? {
        val present = names.associateBy { it.lowercase() }
        return fileNames.firstNotNullOfOrNull { present[it] }
    }
}
