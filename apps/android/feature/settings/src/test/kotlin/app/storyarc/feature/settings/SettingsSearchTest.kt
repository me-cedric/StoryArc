package app.storyarc.feature.settings

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The settings index, which is a hand-written list and therefore the kind of thing that
 * rots quietly.
 *
 * Mirrored case for case by iOS's `SettingsSearchTests`, bar one entry. The two indexes are
 * the one place a reader can tell the platforms apart without opening a screen, so they are
 * asserted against the same expectations rather than merely written to the same spec. The
 * exception is `DYNAMIC_COLOUR`: Material You is Android's, so iOS has no such setting and
 * no such row to assert.
 */
class SettingsSearchTest {
    @Test
    fun `an empty query lists every group and no single setting`() {
        val matches = SettingsGroup.search("")

        assertEquals(SettingsGroup.entries, matches.map { it.group })
        assertTrue(matches.all { it.anchor == null })
    }

    @Test
    fun `whitespace is not a query`() {
        assertEquals(SettingsGroup.entries.size, SettingsGroup.search("   ").size)
    }

    @Test
    fun `a term that names a setting points at the setting, not at its group`() {
        val matches = SettingsGroup.search("volume")

        assertEquals(1, matches.size)
        assertEquals(SettingsAnchor.VOLUME_BUTTONS, matches.first().anchor)
        // The group path, which is what makes the match actionable.
        assertEquals(SettingsGroup.READING, matches.first().group)
    }

    @Test
    fun `case is not part of a query`() {
        assertEquals(SettingsAnchor.VOLUME_BUTTONS, SettingsGroup.search("VOLUME").first().anchor)
    }

    @Test
    fun `a query nothing answers returns nothing`() {
        assertTrue(SettingsGroup.search("zzzz").isEmpty())
    }

    /**
     * The test that keeps the index honest: an anchor no term reaches is a highlight
     * nothing can ask for, and the screen would carry the tint code for a row search
     * cannot send anyone to.
     */
    @Test
    fun `every setting the screens can highlight is reachable by search`() {
        val indexed = SEARCHABLE.mapNotNull { it.second.anchor }.toSet()

        assertEquals(SettingsAnchor.entries.toSet(), indexed)
    }

    @Test
    fun `every group is reachable by search`() {
        val indexed = SEARCHABLE.filter { it.second.anchor == null }.map { it.second.group }.toSet()

        assertEquals(SettingsGroup.entries.toSet(), indexed)
    }

    @Test
    fun `every term finds the entry that claims it`() {
        SEARCHABLE.forEach { (terms, match) ->
            terms.forEach { term ->
                val found = SettingsGroup.search(term).map { it.id }
                assertTrue("\"$term\" does not find ${match.id}", found.contains(match.id))
            }
        }
    }

    /**
     * An anchor carries its own group, so a match cannot claim a setting is on a screen
     * that does not show it.
     */
    @Test
    fun `a setting match agrees with its anchor about where the setting lives`() {
        SettingsAnchor.entries.forEach { anchor ->
            assertEquals(anchor.group, SettingMatch.of(anchor).group)
        }
    }

    @Test
    fun `a group match and a setting match are told apart by their identity`() {
        assertNotEquals(
            SettingMatch.of(SettingsGroup.READING).id,
            SettingMatch.of(SettingsAnchor.VOLUME_BUTTONS).id,
        )
    }
}
