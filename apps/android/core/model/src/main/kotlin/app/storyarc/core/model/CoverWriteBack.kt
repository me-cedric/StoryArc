package app.storyarc.core.model

/**
 * What a chosen cover was set on, from the point of view of writing it back to a source.
 *
 * Every row a reader can set a cover on is one of these, so [CoverWriteBack.offer] is total
 * and a new row has to choose a case rather than fall through to an offer.
 */
sealed class CoverWriteSubject {
    /**
     * A reading list on a Kavita server.
     *
     * `promoted` is the only ownership signal a client gets. Kavita answers
     * `ReadingList/lists` with the lists the signed-in reader owns plus the promoted ones,
     * so a list that is **not** promoted in that answer is necessarily theirs. A promoted
     * list may belong to anybody, which is why it is not offered.
     */
    data class KavitaReadingList(val id: Int, val promoted: Boolean) : CoverWriteSubject()

    data object KavitaSeries : CoverWriteSubject()

    data object KavitaChapter : CoverWriteSubject()

    data object KavitaCollection : CoverWriteSubject()

    data object KavitaLibrary : CoverWriteSubject()

    /** Any row from an OPDS catalogue, of either version. */
    data object Opds : CoverWriteSubject()

    /** A file or folder on this device, which has no server to write to. */
    data object LocalFile : CoverWriteSubject()
}

/** Whether the app offers to write a cover back, and to what. */
sealed class CoverWriteOffer {
    /** Nothing is offered. The cover stays on this device. */
    data object None : CoverWriteOffer()

    /** Kavita's reading-list cover route, for the list with this identifier. */
    data class KavitaReadingList(val id: Int) : CoverWriteOffer()
}

/**
 * The one place that decides whether a write-back is offered.
 *
 * `cover-art` requires the app to offer a write "only where that source accepts one from the
 * reader who is signed in, and SHALL NOT offer it anywhere else". Kavita has six
 * cover-upload routes and five of them need the administrator role, so an offer on a series,
 * a chapter, a collection or a library is a button that answers 403 to most readers -- which
 * teaches them the app is broken. OPDS has no write operation in version 1.2 or 2.0, so
 * there is nothing there to offer either.
 *
 * One function rather than a condition at each call site, because the drift this guards
 * against is a later screen growing its own copy of the condition and getting it wrong.
 * iOS's `CoverWriteBack` decides the same way.
 */
object CoverWriteBack {
    fun offer(subject: CoverWriteSubject): CoverWriteOffer = when (subject) {
        is CoverWriteSubject.KavitaReadingList ->
            if (subject.promoted) {
                CoverWriteOffer.None
            } else {
                CoverWriteOffer.KavitaReadingList(subject.id)
            }
        CoverWriteSubject.KavitaSeries,
        CoverWriteSubject.KavitaChapter,
        CoverWriteSubject.KavitaCollection,
        CoverWriteSubject.KavitaLibrary,
        CoverWriteSubject.Opds,
        CoverWriteSubject.LocalFile,
        -> CoverWriteOffer.None
    }
}
