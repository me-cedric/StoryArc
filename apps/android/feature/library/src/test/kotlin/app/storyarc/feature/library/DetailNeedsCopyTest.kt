package app.storyarc.feature.library

import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasProgressBarRangeInfo
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.Download
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The page for a publication with no copy on the device, whose library is answering.
 *
 * **The defect this pins.** The page drew *Read* for a catalogue row. Nothing failed when it
 * was pressed: such a row carries a server identifier and no path, so the reader was handed a
 * button whose whole effect was to return from the function that would have opened the book.
 * The download was absent from the primary position and from the overflow at the same time, so
 * the page offered no way to get the file either.
 *
 * `publication-detail` states the rule the page now keeps: "the primary action is never one
 * that fails when it is taken", and for this publication it "is to obtain the copy and its
 * wording says so", with "no action on the page [offering] to read it, in the primary position
 * or anywhere else".
 *
 * **Composed rather than asserted as rules alone.** `DetailActionsTest` pins what
 * [primaryActionOf] answers, and it would have gone on passing while nothing on the page asked
 * it -- the defect was one call site short of an argument. So the decision function is called
 * *here*, from the facts the page holds, and the controls it produces are the assertion.
 *
 * `GraphicsMode.NATIVE` for the reason `ListOrderChipsWrapTest` gives: legacy graphics measure
 * a glyph at about a pixel wide, so a control drawn off the window still passes under them.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
// Robolectric ships an image per API level and has none for 37, so it cannot be handed the
// module's target. 34 is inside its range and above the minimum this app supports.
@Config(sdk = [34], qualifiers = "w411dp-h891dp")
class DetailNeedsCopyTest {

    @get:Rule
    val compose = createComposeRule()

    /**
     * Whether a copy is on the device, which is the one fact a finished download changes.
     *
     * A state rather than a parameter, so one test can watch the copy *arrive* while the page
     * is open -- the delta's own scenario, and the one a page rebuilt from scratch cannot show.
     */
    private val here = mutableStateOf(false)

    /**
     * A row exactly as `OpdsContributor` files one: a server identifier, no path, no size, and
     * the `StreamingCapability.STREAMS` default that nobody stated.
     */
    private val row = Publication(
        identity = PublicationIdentity(
            serverIdentifier = PublicationIdentity.ServerIdentifier(
                sourceId = SOURCE,
                remoteId = "opds:the-ridge-road",
            ),
        ),
        format = PublicationFormat.CBZ,
        displayTitle = "The Ridge Road",
        origin = MetadataOrigin.AUTHORITATIVE,
        sourceId = SOURCE,
    )

    /** The library answers, and it holds no copy of this one. */
    private val answering = Provenance(
        place = Provenance.Place.LIBRARY,
        libraryName = "Beach Library",
        readiness = Provenance.Readiness.NOT_DOWNLOADED,
        isAlsoElsewhere = false,
    )

    private val onDevice = Provenance(
        place = Provenance.Place.DEVICE,
        libraryName = null,
        readiness = Provenance.Readiness.READY,
        isAlsoElsewhere = false,
    )

    /**
     * The page, with every decision taken the way `PublicationDetailScreen` takes it.
     *
     * @param readsWhereItLies whether anything can open this publication at the address it
     *   has. False for a catalogue row, because `smb` is the only remote scheme
     *   `PublicationAccess` holds a reader for -- so this is the answer the screen supplies.
     */
    private fun show(
        transfer: Download? = null,
        readsWhereItLies: Boolean = false,
        /** The catalogue route: what `PublicationCopy.start` is for an OPDS row. */
        copyStart: (() -> Unit)? = null,
        /** The app layer's route, for a publication that has a location to fetch from. */
        onCopyFromLocation: (() -> Unit)? = {},
    ) {
        compose.setContent {
            StoryArcTheme {
                val provenance = if (here.value) onDevice else answering
                val action = primaryActionOf(
                    publication = row,
                    provenance = provenance,
                    isOnDevice = here.value,
                    hasProgress = false,
                    readsWhereItLies = here.value || readsWhereItLies,
                )
                // **Both routes, combined first, exactly as the screen combines them.** A
                // publication reaches a copy through its catalogue entry or through its
                // location, never both, and the control takes whichever it has. The screen
                // handed the controls the location route alone, so every catalogue row —
                // which has only the other one — drew no download control at all.
                val obtain = copyStart ?: onCopyFromLocation
                DetailMainPane(
                    publication = row,
                    cover = null,
                    accent = null,
                    action = action,
                    provenance = provenance,
                    transfer = transfer,
                    onRead = {},
                    // The screen's own partition: the copy goes to the primary control or to
                    // the overflow, never to both. This pane is the primary one.
                    onDownload = obtain.takeIf {
                        downloadControl(action, obtain != null) == DownloadControl.PRIMARY
                    },
                )
            }
        }
    }

    @Test
    fun `a row with no copy asks for one and says why, and offers no read`() {
        show()

        compose.onNodeWithText("Download it").assertIsDisplayed()
        compose.onNodeWithText("This one has to be on your device before it opens.")
            .assertIsDisplayed()

        // The four words the page must not say for this publication. Each is a `PrimaryAction`
        // that opens the book, and the first of them was what the page actually drew.
        compose.onNodeWithText("Read").assertDoesNotExist()
        compose.onNodeWithText("Continue").assertDoesNotExist()
        compose.onNodeWithText("Listen").assertDoesNotExist()
        compose.onNodeWithText("Continue listening").assertDoesNotExist()

        // "or anywhere else", which on this page is the overflow. The menu carries no read item
        // of its own, so what is left to pin is the other half of the partition: the copy is the
        // primary control, and the screen therefore hands the overflow nothing.
        val action = primaryActionOf(row, answering, isOnDevice = false, hasProgress = false, readsWhereItLies = false)
        assertEquals(PrimaryAction.NEEDS_DOWNLOAD, action)
        assertEquals(DownloadControl.PRIMARY, downloadControl(action, canDownload = true))
    }

    @Test
    fun `the copy arriving turns the page into a read`() {
        show()
        compose.onNodeWithText("Download it").assertIsDisplayed()

        // `publication-detail`'s *The copy arrives while the page is open*: "the primary action
        // becomes the read and opens the copy", and the page "states it is now readable with no
        // network" -- which is the provenance line, because a copy on the device is on the
        // device whichever library it was fetched from.
        here.value = true
        compose.waitForIdle()

        compose.onNodeWithText("Read").assertIsDisplayed()
        compose.onNodeWithText("This one has to be on your device before it opens.")
            .assertDoesNotExist()
        compose.onNodeWithText("On this device").assertIsDisplayed()
    }

    @Test
    fun `a transfer with no stated size says a copy is coming and invents no number`() {
        // An OPDS acquisition link carries no length, so this is the state every download from
        // this page starts in. `offline-downloads`: a fabricated size "is worse than an honest
        // blank", and a determinate bar is that fabrication drawn to scale.
        show(transfer = transfer(Download.State.Running))

        compose.onNodeWithText("Downloading").assertIsDisplayed()
        compose.onNode(hasProgressBarRangeInfo(ProgressBarRangeInfo.Indeterminate))
            .assertIsDisplayed()
    }

    @Test
    fun `a transfer says how far the copy has come once the library states a size`() {
        show(
            transfer = transfer(Download.State.Running)
                .copy(expectedBytes = 400, downloadedBytes = 100),
        )

        compose.onNode(hasProgressBarRangeInfo(ProgressBarRangeInfo(0.25f, 0f..1f)))
            .assertIsDisplayed()
    }

    @Test
    fun `a transfer that is waiting says what it is waiting for`() {
        show(transfer = transfer(Download.State.Paused(Download.Pause.WAITING_FOR_WIFI)))

        compose.onNodeWithText("Waiting for Wi-Fi").assertIsDisplayed()
        // Not both. A held transfer described as downloading is the page stating something
        // untrue, and a bare fraction could never have avoided it.
        compose.onNodeWithText("Downloading").assertDoesNotExist()
    }

    private fun transfer(state: Download.State) = Download(
        id = "the-ridge-road",
        title = "The Ridge Road",
        remote = "https://books.example/the-ridge-road.cbz",
        mediaType = "application/vnd.comicbook+zip",
        state = state,
    )

    /**
     * **A catalogue row can be fetched from its own page.**
     *
     * Its copy route is the catalogue entry, and it has no location — so `onCopyFromLocation`
     * is null and the control has to come from the other half. The page drew *This one has to
     * be on your device before it opens* and offered nothing that could put it there: not the
     * primary action, not the overflow. Seen on an emulator on 2026-09-12 against a mock OPDS
     * catalogue, with the entry resolved and its acquisition in hand.
     */
    @Test
    fun `a catalogue row offers the copy though it has no location to fetch from`() {
        show(copyStart = {}, onCopyFromLocation = null)

        compose.onNodeWithText("Download it").assertIsDisplayed()
        compose.onNodeWithText("This one has to be on your device before it opens.")
            .assertIsDisplayed()
    }

    /** And a row with neither route offers no control, which is the other side of the rule. */
    @Test
    fun `a row with no route to a copy offers no download`() {
        show(copyStart = null, onCopyFromLocation = null)

        compose.onNodeWithText("Download it").assertDoesNotExist()
    }

}

private val SOURCE: UUID = UUID.fromString("00000000-0000-0000-0000-0000000000ab")
