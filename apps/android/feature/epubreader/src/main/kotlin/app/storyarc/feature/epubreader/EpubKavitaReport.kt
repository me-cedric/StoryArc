package app.storyarc.feature.epubreader

import android.content.Context
import app.storyarc.core.kavita.KavitaAddress
import app.storyarc.core.kavita.KavitaClient
import app.storyarc.core.kavita.KavitaExchange
import app.storyarc.core.kavita.KavitaPosition
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
import app.storyarc.core.model.reachesOnlyAnotherDevice
import app.storyarc.core.persistence.CredentialStore
import app.storyarc.core.persistence.KavitaOrigin
import app.storyarc.core.persistence.KavitaProgressStore
import app.storyarc.core.persistence.KavitaUnsent
import app.storyarc.core.persistence.ProgressStore
import app.storyarc.core.persistence.SourceStore

/**
 * Tells the server where the reader got to, when this book came from one.
 *
 * `kavita-server` sends a position "when a user reads a Kavita publication and leaves the
 * reader". [ReaderHost] in the app module does the same for the comic and PDF reader; this
 * is [EpubReaderActivity]'s own screen and outside that composable entirely, so it reports
 * on its own `onStop` instead, which is the twin of leaving that host answers.
 *
 * Small deliberate duplication rather than a dependency on `feature:library`: no feature
 * module here depends on another, and what this needs from `KavitaSync.report` and
 * `KavitaPage.of` is three lines each, already reachable through `core:kavita` and
 * `core:persistence`.
 */
internal suspend fun reportToKavita(context: Context, identity: PublicationIdentity) {
    val kavitaProgress = KavitaProgressStore.open(context)
    val origin = kavitaProgress.origin(identity.stableId) ?: return
    val progress = ProgressStore.open(context)
    val recorded = progress.progress(identity) ?: return
    val page = pageToReport(recorded.position, origin) ?: return
    val address = SourceStore.open(context).registry().sources
        .firstOrNull { it.id.toString() == origin.sourceId }
        ?.let { kavitaAddressOf(it, CredentialStore.open(context)) }
    val unsent = KavitaUnsent(origin, page)
    // No address is the "not there" case `KavitaSync.report` holds for, not a reason to drop.
    if (address == null) return kavitaProgress.hold(unsent)
    val sent = runCatching {
        KavitaClient(address).report(
            KavitaPosition(
                libraryId = origin.libraryId,
                seriesId = origin.seriesId,
                volumeId = origin.volumeId,
                chapterId = origin.chapterId,
                pageNum = page,
            ),
        )
    }
    if (sent.isSuccess) {
        kavitaProgress.drop(unsent.key)
        // So the next pull's merge sees this record as untouched rather than as "changed
        // since last sync".
        progress.save(KavitaExchange.settled(recorded))
    } else {
        kavitaProgress.hold(unsent)
    }
}

/**
 * The page number a recorded position reports to Kavita, or null when there is nothing to
 * convert it with.
 *
 * A reflowable position -- this reader's own -- carries no page number, only a fraction.
 * [KavitaExchange.pageNumber] turns a fraction into a page, and needs the chapter's own
 * length to do it, which is why [KavitaOrigin] carries it. `origin.pages == 0` means an
 * origin remembered before that field existed, or a chapter the server never reported a
 * length for -- nothing to convert against, so nothing is sent.
 *
 * [ReaderHost] in the app module answers the same question for the comic and PDF reader,
 * over the same two cases; kept apart because a `feature` module here does not depend on
 * another one, `app` included.
 */
internal fun pageToReport(position: ReadingPosition, origin: KavitaOrigin): Int? = when (position) {
    is ReadingPosition.Page -> position.index
    is ReadingPosition.Reflowable, is ReadingPosition.Listening ->
        if (origin.pages > 0) KavitaExchange.pageNumber(position, origin.pages) else null
}

/**
 * The address a saved Kavita source answers requests at, or null when it is not one, has no
 * address, or has lost its key -- the last of which is what `unauthorized` means and needs
 * the reader to fix.
 *
 * `feature.library`'s `KavitaPage.of` answers the same question; duplicated for the reason
 * [pageToReport] gives.
 */
internal fun kavitaAddressOf(source: Source, credentials: CredentialStore?): KavitaAddress? {
    if (source.kind != SourceKind.KAVITA_SERVER || source.reachesOnlyAnotherDevice) return null
    val base = source.locator ?: return null
    val reference = source.credentialReference ?: return null
    val key = credentials?.secret(reference) ?: return null
    return KavitaAddress(base, key)
}
