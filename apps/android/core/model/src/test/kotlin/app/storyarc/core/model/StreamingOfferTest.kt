package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

/**
 * `publication-formats`' two remote scenarios of *Streaming capability per format*, asserted
 * case for case. iOS's `StreamingOfferTests` asserts the same cases.
 *
 * The pair is the point. A publication that cannot be streamed owes the reader a sentence, a
 * size and an offer *before* anything is transferred; the same publication once it is on the
 * device owes them nothing at all, "because the constraint was never about the format being
 * readable". One rule has to give both answers, or the second turns into a notice on every
 * solid comic a reader has already downloaded.
 */
class StreamingOfferTest {

    @Test
    fun `a solid archive on a share is offered as a download, with its size`() {
        // The scenario: "the app says the format has to be downloaded before it can be read,
        // states the size, and offers to download it".
        assertEquals(
            StreamingOffer.Download(1_050L),
            StreamingOffer.of(
                streaming = StreamingCapability.DOWNLOAD_ONLY,
                isLocal = false,
                readsWhereItLies = true,
                bytes = 1_050L,
            ),
        )
    }

    @Test
    fun `it is never handed to a reader to stream badly`() {
        // The other half of the same scenario: "it does not begin streaming badly and leave
        // the user watching a stalled page". `readsWhereItLies` is true here -- the container
        // would happily supply page one -- and the answer is still not Open.
        assertNotEquals(
            StreamingOffer.Open,
            StreamingOffer.of(
                streaming = StreamingCapability.DOWNLOAD_ONLY,
                isLocal = false,
                readsWhereItLies = true,
                bytes = null,
            ),
        )
    }

    @Test
    fun `a download-only publication already on the device opens with no notice`() {
        // "A solid archive already downloaded ... opens directly with no notice." Open is
        // that: nothing to say, nothing to confirm, no size to state.
        assertEquals(
            StreamingOffer.Open,
            StreamingOffer.of(
                streaming = StreamingCapability.DOWNLOAD_ONLY,
                isLocal = true,
                readsWhereItLies = false,
                bytes = 1_050L,
            ),
        )
    }

    @Test
    fun `a refusal is a refusal once the bytes are here, and no transfer is offered`() {
        // Solid RAR4. "It does not hold for solid RAR4, which is refused whether local or
        // remote" -- and a download that changes nothing must not be offered.
        assertEquals(
            StreamingOffer.Refuse,
            StreamingOffer.of(
                streaming = StreamingCapability.REFUSED,
                isLocal = true,
                readsWhereItLies = false,
                bytes = 400L,
            ),
        )
    }

    @Test
    fun `a remote record marked refused is fetched rather than declined`() {
        // `PublicationIndexer.index(source, ...)` marks a solid archive met over a share
        // REFUSED before any file exists to judge. Believing that as a refusal would decline
        // to fetch the very publication the first scenario is about.
        assertEquals(
            StreamingOffer.Download(9_000L),
            StreamingOffer.of(
                streaming = StreamingCapability.REFUSED,
                isLocal = false,
                readsWhereItLies = false,
                bytes = 9_000L,
            ),
        )
    }

    @Test
    fun `a decoder that cannot work from a source is a download whatever the container said`() {
        assertEquals(
            StreamingOffer.Download(42L),
            StreamingOffer.of(
                streaming = StreamingCapability.STREAMS,
                isLocal = false,
                readsWhereItLies = false,
                bytes = 42L,
            ),
        )
    }

    @Test
    fun `a streamable publication on a share is read where it lies`() {
        // `network-share`'s whole promise, and this rule must not cost it: a CBZ on a NAS
        // still opens from its headers.
        assertEquals(
            StreamingOffer.Open,
            StreamingOffer.of(
                streaming = StreamingCapability.STREAMS,
                isLocal = false,
                readsWhereItLies = true,
                bytes = 400_000_000L,
            ),
        )
    }

    @Test
    fun `an unstated length is offered as an absence rather than as a zero`() {
        // `offline-downloads` is explicit that a fabricated size is worse than an honest
        // blank, and a zero would read as a free download.
        assertEquals(
            StreamingOffer.Download(null),
            StreamingOffer.of(
                streaming = StreamingCapability.DOWNLOAD_ONLY,
                isLocal = false,
                readsWhereItLies = false,
                bytes = null,
            ),
        )
    }
}
