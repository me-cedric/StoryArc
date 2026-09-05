package app.storyarc.feature.library

import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.assertHeightIsEqualTo
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The page for a publication with no series, no year, no description and no cover.
 *
 * Task 2.4's four absences, which nothing on either platform asserted. The delta asks for two
 * things at once and they are easy to confuse: the lines are "absent rather than shown empty
 * or filled with a placeholder", **and** "the page's composition holds together with only a
 * cover and a title".
 *
 * **This file answers the first and can only gesture at the second.** Whether four fifths of
 * a tablet window of empty wash "holds together" is a judgement about a picture, and
 * `after-2026-08-31/android-detail-from-a-cover-light.png` is on record saying it does not.
 * That is a layout decision still owed, and no assertion here should be read as closing it.
 *
 * iOS asserts the same four answers as pure rules in `DetailAbsencesTests.swift`, because its
 * host suite composes nothing. Robolectric lets Android draw them, which is the stronger
 * reach for exactly one of the four: the subtitle slot being *empty* rather than *blank* is a
 * fact about what is measured, not about what a function returned.
 *
 * `GraphicsMode.NATIVE` for `ListOrderChipsWrapTest`'s reason: legacy graphics measure every
 * string as roughly a pixel per glyph, so a height assertion under them measures nothing.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
// Robolectric ships an image per API level and has none for 37, so it cannot be handed the
// module's target. 34 is inside its range and above the minimum this app supports.
@Config(sdk = [34], qualifiers = "w411dp-h891dp")
class DetailAbsencesTest {

    @get:Rule
    val compose = createComposeRule()

    /** The degenerate page: a title, and nothing else to say about it. */
    private val bare = Publication(
        identity = PublicationIdentity(contentDigest = "bare"),
        format = PublicationFormat.CBZ,
        displayTitle = "The Ridge Road",
        origin = MetadataOrigin.AUTHORITATIVE,
    )

    private val full = bare.copy(series = "Ashfall", number = "1", year = 2024)

    @Test
    fun `a publication with no series and no year leaves the subtitle slot empty`() {
        // Empty rather than blank, and the difference is the whole clause. `DetailSubtitle`
        // returns before composing anything when `listOfNotNull` comes back empty, so the
        // app bar's subtitle slot has no child at all -- rather than a `Text("")` reserving
        // a line of the bar's height for a fact the publication does not carry.
        val state = mutableStateOf(bare)
        compose.setContent { StoryArcTheme { DetailSubtitle(state.value) } }
        compose.waitForIdle()

        compose.onRoot().assertHeightIsEqualTo(0.dp)

        // The control. Without it a subtitle that had stopped drawing for any reason at all
        // would pass this test, which is the shape of a check that cannot fail.
        state.value = full
        compose.waitForIdle()
        // **`Ashfall #1`, not `Ashfall · #1`, and that is a deliberate change.** The page used
        // to join the series and the number with its own separator, while the grid caption, the
        // list caption and iOS all render `seriesLine`'s `Ashfall #1`. One publication read two
        // ways depending on which surface was showing it. The page now goes through the same
        // rule, which is also what stops it printing a standalone's title twice.
        compose.onNodeWithText("Ashfall #1 · 2024").assertExists()
    }

    @Test
    fun `the page with nothing to say still draws its cover well and its one action`() {
        // The composition the delta says has to hold together. What is left when the series,
        // the year, the description and the cover are all absent: the placeholder well
        // naming the format, and the one thing the page wants the reader to do.
        compose.setContent {
            StoryArcTheme {
                DetailMainPane(
                    publication = bare,
                    cover = null,
                    accent = null,
                    action = PrimaryAction.READ,
                    provenance = Provenance(
                        place = Provenance.Place.DEVICE,
                        libraryName = null,
                        readiness = Provenance.Readiness.READY,
                        isAlsoElsewhere = false,
                    ),
                    downloadFraction = null,
                    onRead = {},
                    onDownload = null,
                )
            }
        }
        compose.waitForIdle()

        // The app's own placeholder, per the delta -- and the format rather than a generic
        // glyph, because `publication-formats` forbids an unnamed one.
        //
        // `useUnmergedTree`, and that is a fact about the page rather than a workaround.
        // `DetailCover` carries `clearAndSetSemantics {}`: the well is decoration, the title
        // is read out of the app bar, and announcing "CBZ" after it would be a stutter. So
        // the placeholder is deliberately absent from the merged tree a screen reader walks,
        // and the only honest way to assert it is drawn is to look past the merge.
        compose.onNodeWithText("CBZ", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("Read").assertExists()
    }

    @Test
    fun `a description the publication does not carry is absent rather than empty`() {
        // Both halves of Android's `takeIf { it.isNotBlank() }`: no description at all, and a
        // description of whitespace. The second is the one iOS was getting wrong -- it read
        // `!summary.isEmpty` until 2026-09-05, so three spaces drew a paragraph of the page's
        // own spacing with nothing in it. Asserted here as well as there because the answer
        // is meant to be the same on both, and only one of the two suites would have caught
        // it drifting back.
        val state = mutableStateOf(bare)
        compose.setContent {
            StoryArcTheme {
                DetailMainPane(
                    publication = state.value,
                    cover = null,
                    accent = null,
                    action = PrimaryAction.READ,
                    provenance = Provenance(
                        place = Provenance.Place.DEVICE,
                        libraryName = null,
                        readiness = Provenance.Readiness.READY,
                        isAlsoElsewhere = false,
                    ),
                    downloadFraction = null,
                    onRead = {},
                    onDownload = null,
                )
            }
        }
        compose.waitForIdle()
        compose.onNodeWithText(SUMMARY).assertDoesNotExist()

        state.value = bare.copy(summary = "   ")
        compose.waitForIdle()
        compose.onNodeWithText("   ").assertDoesNotExist()

        // And the control: a real description does reach the page.
        state.value = bare.copy(summary = SUMMARY)
        compose.waitForIdle()
        compose.onNodeWithText(SUMMARY).assertExists()
    }
}

private const val SUMMARY = "Nine years after the ash, a courier walks the ridge road."
