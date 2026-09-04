package app.storyarc.feature.library

/**
 * Where one library scan walks.
 *
 * The app's own folder **and** every folder the reader picked — never one or the other.
 * That distinction is the whole of this file: `rescan` used to walk the managed folder only
 * when no folder had been picked, so adding the first source silently stopped it, and the
 * reconciliation that ends a walk then removed every publication the walk had not met. A
 * reader who connected a second library lost the first one until they removed the source
 * again, which is not a step anybody would guess at.
 *
 * The managed folder is not a source and never becomes one — it is where a file shared to
 * StoryArc lands, and where the emulator and the instrumented tests put a corpus. So it has
 * to be walked on every scan, exactly like a picked tree, and a publication found in it is
 * unattributed rather than pretending to belong to a library the reader chose.
 *
 * Trees arrive as strings and the managed folder as `null`, because a `Uri` cannot be built
 * in a JVM unit test and the caller already carries the same `Uri?` shape. The same split
 * [SourceRemoval] makes.
 */
internal object ScanTargets {

    /**
     * The walks one scan performs, in order: the app's own folder first, then each picked
     * tree once.
     *
     * The app's own folder leads because it needs no provider round-trip, so the first rows
     * on the shelf are the ones already on the device. Duplicates are dropped — a tree that
     * is in the picked set twice is one folder, and walking it twice opens every archive in
     * it twice.
     *
     * @param trees the picked folders, as their tree `Uri`s rendered to strings.
     * @return one entry per walk; `null` is the app's own managed folder.
     */
    fun of(trees: List<String>): List<String?> = listOf(null) + trees.distinct()
}
