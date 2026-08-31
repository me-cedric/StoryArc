package app.storyarc.core.format

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * What a folder of files is, decided from its entries.
 *
 * `publication-formats` lists a plain folder of ordered images as a publication and
 * now lists a folder of ordered audio as one too, so a folder has to be *asked* which
 * it is. The rule it gives for a folder holding both is a majority, and the
 * requirement that the app "states which it chose" is why this returns an answer
 * rather than silently picking. iOS's `FolderKindTests` asserts the same table.
 */
class FolderKindTest {
    @Test
    fun `a folder of images is a comic`() {
        assertEquals(
            FolderKind.COMIC,
            FolderKind.of(listOf("page1.png", "page2.jpg", "page3.webp")),
        )
    }

    @Test
    fun `a folder of audio is an audiobook`() {
        assertEquals(
            FolderKind.AUDIOBOOK,
            FolderKind.of(listOf("part1.mp3", "part2.m4b", "part3.flac")),
        )
    }

    @Test
    fun `a folder holding both is the kind most of its entries are`() {
        // The corpus fixture: two audio files and one cover image.
        assertEquals(
            FolderKind.AUDIOBOOK,
            FolderKind.of(listOf("part1.mp3", "part2.mp3", "cover.png")),
        )
        // And the mirror, which is the far commoner case — a comic folder that
        // happens to carry a theme tune should not become an audiobook.
        assertEquals(
            FolderKind.COMIC,
            FolderKind.of(listOf("p1.png", "p2.png", "theme.mp3")),
        )
    }

    @Test
    fun `a tie is a comic`() {
        // A **product decision**, not a rule from anywhere: a folder of images is what
        // StoryArc has always made of a folder, and a tie is the one case where
        // deciding otherwise would change existing behaviour for no stated reason.
        assertEquals(FolderKind.COMIC, FolderKind.of(listOf("p1.png", "part1.mp3")))
    }

    @Test
    fun `entries that are neither are not counted`() {
        // The same exclusions pages already have: resource forks, dotfiles and
        // metadata are not evidence of anything, so a folder of one page and four
        // `.DS_Store`s is still a comic rather than a folder with no majority.
        assertEquals(
            FolderKind.COMIC,
            FolderKind.of(
                listOf(
                    "page1.png",
                    ".DS_Store",
                    "._page1.png",
                    "__MACOSX/page1.png",
                    "ComicInfo.xml",
                ),
            ),
        )
    }

    @Test
    fun `a folder of nothing recognisable has no kind`() {
        // Not a comic by default: the caller has to be able to say "this folder holds
        // no publication" rather than open an empty one.
        assertNull(FolderKind.of(listOf("notes.txt", "cover.psd")))
        assertNull(FolderKind.of(emptyList()))
    }

    @Test
    fun `the corpus's own folders are what the manifest says they are`() {
        // Read from disk rather than from a literal, so this fails if the fixtures are
        // regenerated differently.
        val expected = mapOf(
            "audiobooks/folder-parts" to FolderKind.AUDIOBOOK,
            "audiobooks/mixed-folder" to FolderKind.AUDIOBOOK,
        )

        for ((folder, kind) in expected) {
            val names = FixtureCorpus.file(folder).list()?.toList() ?: emptyList()
            assertEquals(folder, kind, FolderKind.of(names))
        }
    }
}
