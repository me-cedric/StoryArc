package app.storyarc.feature.library

import androidx.compose.ui.res.stringResource
import androidx.compose.ui.test.junit4.v2.createComposeRule
import app.storyarc.core.model.LibrarySort
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * A chip carrying the current sort says that it is a sort, in every language this app ships.
 *
 * `library-browsing`, *An ordering says that it is an ordering*: "a reader seeing the field
 * name alone cannot tell a sort from a filter — and the same holds for grouping, which is
 * neither".
 *
 * **The defect was photographable and was photographed.** The shelf's chip row read *On this
 * device · Title · Filter* — see
 * `docs/designs/screenshots/sort-chip-2026-09-01/before-light-default.png`. Two of those three
 * chips narrow what is on the shelf and the middle one does not, and the middle one was the
 * only one whose label was a bare noun. *Title* between them is a filter value to anyone who
 * has not already learnt the row.
 *
 * **What is asserted is a property, not a spelling.** A test comparing the label to `"Sort:
 * Title"` would pin the copy in one language and pin nothing at all in the other three, and
 * would have to be rewritten by whoever next improves the wording. So each locale is checked
 * for the two things the requirement actually asks:
 *
 * 1. the label is **not** the bare field name — that is the defect, stated directly;
 * 2. the field name is **still in** it, because a chip that said only *Sort* would satisfy
 *    rule 1 by telling the reader less than before.
 *
 * Both are needed. Rule 1 alone passes for a label of pure decoration; rule 2 alone passes for
 * the bare name this replaced.
 *
 * **All seven fields, not just the one the review named.** *Title* is the default and so the
 * one a screenshot catches, and a frame applied only to the default is a frame that vanishes
 * the moment a reader changes the sort — which is exactly when they most need to be told what
 * the chip is.
 *
 * No `GraphicsMode.NATIVE` here, unlike the two chip-wrap fixtures beside it: nothing is
 * measured, so Robolectric's glyph width cannot lie to this file. What it *can* do is resolve
 * resources, which is the whole subject.
 *
 * `ScopeChipsWrapTest` and `ListOrderChipsWrapTest` cover the other half of this change — that
 * a longer label still fits the row it is drawn in.
 */
@RunWith(RobolectricTestRunner::class)
// Robolectric ships an image per API level and has none for 37, so it cannot be handed the
// module's target. 34 is inside its range and above the minimum this app supports, and the
// question here — what a string resource resolves to — has no API level in it.
@Config(sdk = [34])
class SortChipNamesAnOrderingTest {

    @get:Rule
    val compose = createComposeRule()

    @Test
    fun `every ordering says it is one in English`() = assertEveryOrderingSaysSo()

    @Test
    @Config(qualifiers = "de-rDE")
    fun `every ordering says it is one in German`() = assertEveryOrderingSaysSo()

    @Test
    @Config(qualifiers = "es-rES")
    fun `every ordering says it is one in Spanish`() = assertEveryOrderingSaysSo()

    @Test
    @Config(qualifiers = "fr-rFR")
    fun `every ordering says it is one in French`() = assertEveryOrderingSaysSo()

    @Test
    fun `the curated order is not dressed as a sort`() {
        // The asymmetry in `ListOrder.chipLabel` is deliberate and this is what holds it.
        // *The list's order* is already named as an ordering, and framing it as one more
        // would claim a sort over the one list whose defining property is that nothing
        // sorted it — `collections-and-reading-lists` makes that order the list's meaning.
        var curated = ""
        var framed = ""
        var bare = ""
        compose.setContent {
            curated = ListOrder.CURATED.chipLabel()
            framed = ListOrder(sort = LibrarySort.TITLE).chipLabel()
            bare = stringResource(R.string.shelves_list_order)
        }
        compose.waitForIdle()

        assertEquals(bare, curated)
        assertNotEquals(bare, framed)
    }

    /**
     * The two rules, over all seven fields, in whichever locale the `@Config` set.
     *
     * The labels are collected inside one composition rather than one per field: the whole
     * point is that the frame is the same frame everywhere, and seven compositions would let
     * seven different answers pass.
     */
    private fun assertEveryOrderingSaysSo() {
        val labels = mutableMapOf<LibrarySort, Pair<String, String>>()
        compose.setContent {
            for (sort in LibrarySort.entries) {
                labels[sort] = stringResource(sort.labelRes) to sortChipLabel(sort)
            }
        }
        compose.waitForIdle()

        assertEquals(LibrarySort.entries.size, labels.size)
        for ((sort, pair) in labels) {
            val (field, chip) = pair
            assertTrue("$sort resolved an empty field name", field.isNotBlank())
            assertNotEquals(
                "The $sort chip reads \"$chip\", which is the bare field name. Beside a chip" +
                    " that says \"Filter\", a bare field name reads as one of its values.",
                field,
                chip,
            )
            assertTrue(
                "The $sort chip reads \"$chip\", which has lost the field name \"$field\"." +
                    " Saying it is a sort without saying which one tells a reader less than" +
                    " the bare name did.",
                chip.contains(field),
            )
        }
    }
}
