package app.storyarc.core.format

import java.io.File

/**
 * A directory of ordered images, read as one publication.
 *
 * `publication-formats` lists a plain folder alongside the archive formats, and it
 * behaves like one: the same page filter, the same natural sort, the same
 * `ComicInfo.xml` handling. The only difference is that there is no container to
 * parse, so this is the one reader with no format work in it at all.
 *
 * Subdirectories are walked, because chapters-as-folders is how unpacked comics
 * are actually laid out — and ordering by full path makes `ch10` follow `ch2` for
 * a folder exactly as it does inside a CBZ.
 */
class ImageFolderArchive private constructor(
    private val root: File,
    override val pages: List<PageEntry>,
    override val skippedPageCount: Int,
    /** `ComicInfo.xml` contents when the folder carries one. */
    val comicInfoData: ByteArray?,
) : ComicArchiveReading {

    /** The folder's parsed metadata, when it carries any. */
    val comicInfo: ComicInfo? by lazy { comicInfoData?.let(ComicInfo::parse) }

    override val coverPage: PageEntry?
        get() = CoverSelection.cover(pages, comicInfo?.coverPageIndex)

    override val doublePageIndices: List<Int>
        get() = PageDeclarations.spreads(pages, comicInfo?.doublePageIndices.orEmpty())


    companion object {
        fun open(directory: File): ImageFolderArchive {
            if (!directory.isDirectory) throw ComicArchiveException.UnrecognisedContainer()
            val root = directory.canonicalFile

            val candidates = mutableListOf<PageEntry>()
            var skipped = 0
            var comicInfo: File? = null

            for (file in root.walkTopDown()) {
                if (!file.isFile) continue
                // Symbolic links are not followed. A publication folder is chosen
                // by the user, but it is still untrusted input: a link pointing
                // outside the root would let a crafted folder read arbitrary
                // files, and no real comic needs one.
                if (file.canonicalFile != file.absoluteFile) continue

                val relative = file.relativeTo(root).invariantSeparatorsPath
                if (relative.lowercase().endsWith("comicinfo.xml")) {
                    comicInfo = file
                    continue
                }
                if (!PageOrdering.isPage(relative)) continue

                // A zero-length file is a page that will never decode. Counting it
                // as skipped is what lets the reader say "opened 10, skipped 2".
                if (file.length() == 0L) {
                    skipped++
                    continue
                }
                candidates += PageEntry(relative, file.length())
            }

            return ImageFolderArchive(
                root = root,
                pages = PageOrdering.sorted(candidates),
                skippedPageCount = skipped,
                comicInfoData = comicInfo?.readBytes(),
            )
        }
    }

    override suspend fun data(page: PageEntry): ByteArray {
        val file = File(root, page.path).canonicalFile
        // Re-checked at read time rather than trusted from the walk: the path came
        // off a filesystem that can change between indexing and reading.
        if (!file.path.startsWith(root.path + File.separator)) {
            throw ComicArchiveException.Unreadable()
        }
        if (!file.isFile) throw ComicArchiveException.Unreadable()
        return file.readBytes()
    }
}
