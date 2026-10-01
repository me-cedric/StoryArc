package app.storyarc.feature.library

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.persistence.speaking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Task 15.6: three count sentences had no plural form, so one title, one found comic or one
 * entry read with a plural verb or noun -- "1 titles", grammatically wrong in every one of
 * the four languages this app ships.
 *
 * French is the assertion here because it inflects the most visibly of the four: a dropped
 * plural shows up as a wrong verb ending or a wrong noun ending, not just a wrong word.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class PluralWordingTest {

    private val french get() =
        (ApplicationProvider.getApplicationContext<Application>() as android.content.Context).speaking("fr")

    @Test
    fun `a library scan found sentence takes a singular participle for one`() {
        val one = french.resources.getQuantityString(R.plurals.library_scanning, 1, 1)
        val many = french.resources.getQuantityString(R.plurals.library_scanning, 3, 3)

        assertEquals("Ajout de vos bandes dessinées — 1 trouvée", one)
        assertEquals("Ajout de vos bandes dessinées — 3 trouvées", many)
        assertNotEquals(one, many)
    }

    @Test
    fun `a promote-entries sentence takes a singular noun for one entry`() {
        val one = french.resources.getQuantityString(R.plurals.shelves_promote_entries, 1, 1, 1)
        val many = french.resources.getQuantityString(R.plurals.shelves_promote_entries, 3, 2, 3)

        assertEquals("1 entrée sur 1", one)
        assertEquals("2 entrées sur 3", many)
        assertNotEquals(one, many)
    }

    @Test
    fun `a sync-conflict sentence takes a singular verb for one title`() {
        val one = french.resources.getQuantityString(R.plurals.sync_conflict_body, 1, 1)
        val many = french.resources.getQuantityString(R.plurals.sync_conflict_body, 2, 2)

        assertEquals(
            "1 titre a avancé à la fois sur cet appareil et dans la bibliothèque d’origine. " +
                "La position la plus avancée a été conservée.",
            one,
        )
        assertEquals(
            "2 titres ont avancé à la fois sur cet appareil et dans la bibliothèque d’origine. " +
                "La position la plus avancée a été conservée.",
            many,
        )
        assertNotEquals(one, many)
    }
}
