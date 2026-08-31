package app.storyarc.core.model

/**
 * What the app may do with a publication it has just met, and what it owes the reader before
 * doing it.
 *
 * `publication-formats`' *Streaming capability per format* says the app "SHALL know which
 * formats can be read remotely and SHALL be honest when one cannot". Its two remote scenarios
 * are the whole of this type:
 *
 * > **WHEN a** publication cannot be read with ranged reads
 * > **THEN** the app says the format has to be downloaded before it can be read, states the
 * > size, and offers to download it
 * > **AND** it does not begin streaming badly and leave the user watching a stalled page
 *
 * > **WHEN** a publication that cannot stream is already available offline
 * > **THEN** it opens directly with no notice, because the constraint was never about the
 * > format being readable
 *
 * [StreamingCapability] was the *classification* those scenarios need and had one reader:
 * `primaryActionOf`, on the publication's own page. A share decided otherwise -- it copied
 * the whole file across whenever the format's decoder wanted a path, without saying so and
 * without naming a size, and handed a container no decoder will open to the reader anyway
 * once the copy landed. This is the answer that decides both, in one place, so the two apps
 * decide alike. iOS keeps the same rule in `StreamingOffer.swift`.
 */
sealed interface StreamingOffer {

    /**
     * Read it where it lies. Also the answer for anything already on the device, which is the
     * second scenario above: a downloaded solid archive opens with no notice, because there is
     * nothing left to say about it.
     */
    data object Open : StreamingOffer

    /**
     * It cannot be read where it lies. The whole file has to come across first, and this is
     * how big it is -- null only where nothing honest can be said about the length, which
     * `offline-downloads` requires to be stated as an absence rather than as a zero.
     */
    data class Download(val bytes: Long?) : StreamingOffer

    /**
     * No decoder will open this, here or anywhere. A solid RAR4: transferring it changes
     * nothing, so the transfer is not offered.
     */
    data object Refuse : StreamingOffer

    companion object {
        /**
         * The offer for one publication.
         *
         * @param streaming what the container reported about itself.
         * @param isLocal whether the bytes are on this device already.
         * @param readsWhereItLies whether the decoder this format needs can work from a ranged
         *   source rather than from a path. Platform truth, and deliberately a parameter:
         *   `PdfRenderer` wants a descriptor and libarchive wants a path here, PDFKit wants a
         *   file on iOS, and the two lists are not the same length. Ignored when [isLocal],
         *   where every decoder has what it wants.
         * @param bytes what the source states the file weighs.
         *
         * **Why [StreamingCapability.REFUSED] is only believed when the bytes are local.**
         * `PublicationIndexer.index(source, ...)` returns a record carrying `REFUSED` for a
         * solid archive it met over a share, and both apps reach that branch before any file
         * exists to judge. Read as a refusal it would decline to fetch the very publication
         * the first scenario is about. Once the file is local the value means what
         * [StreamingCapability.REFUSED] documents, and that is where it is acted on.
         */
        fun of(
            streaming: StreamingCapability,
            isLocal: Boolean,
            readsWhereItLies: Boolean,
            bytes: Long?,
        ): StreamingOffer = when {
            isLocal -> if (streaming == StreamingCapability.REFUSED) Refuse else Open
            streaming == StreamingCapability.DOWNLOAD_ONLY || !readsWhereItLies -> Download(bytes)
            else -> Open
        }
    }
}
