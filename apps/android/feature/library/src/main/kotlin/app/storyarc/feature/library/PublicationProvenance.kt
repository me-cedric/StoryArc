package app.storyarc.feature.library

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.model.Publication
import app.storyarc.core.model.SourceKind
import app.storyarc.core.model.SourceRegistry

/**
 * Where a publication lives, and whether it can be opened right now.
 *
 * `publication-detail` calls this page the seam. `library-browsing` takes origin off the
 * shelf — no server chips, no source line under a cover — and that only holds because
 * origin is *here*, in one line, once. So this is not a decoration on a detail screen: it
 * is the reason every other browse surface is allowed to stay quiet.
 *
 * A value rather than a string, and computed from state the app already holds rather than
 * from a request: "a line that needs a network round trip to draw is a line that will be
 * blank on a train". The wording is [provenanceLabel]'s business and the resources'; what
 * is decided here is *which* of the four things is true.
 */
internal data class Provenance(
    val place: Place,
    /**
     * The reader's own name for the library this came from, or null when it is on the
     * device. Never a URL, a path, a host or an identifier — the delta forbids all four,
     * and a display name is the only thing in the registry that is none of them.
     */
    val libraryName: String?,
    val readiness: Readiness,
    /**
     * Whether this publication is anywhere other than the copy this page will open.
     *
     * The delta: "the line names the one this page will open, and says the publication is
     * also available elsewhere". Without it, a reader who owns the same volume locally and
     * on a server cannot tell which one they are about to read — which is the exact failure
     * taking origin off the shelf would otherwise cause.
     *
     * **Two ways a second place arises, and the two platforms had one each until 2026-09-05.**
     * A copy on the device whose library still exists — the server it was fetched from is the
     * other place, which is what iOS's `alsoIn` had always meant — and another source in the
     * library holding the same publication, which is what this field had always meant.
     * Identity is stable across sources (ADR-0006), so the second is answerable by id. Both
     * are the delta's scenario, so this is the union of them.
     */
    val isAlsoElsewhere: Boolean,
) {
    /** Where a publication lives. Two answers, because the reader only has two places. */
    enum class Place { DEVICE, LIBRARY }

    /**
     * Whether it can be opened right now, which the same line has to answer.
     *
     * [READY] is silent rather than reassuring: a line that says "ready to read" on every
     * publication a reader owns is a line they stop reading, and then it cannot warn them.
     */
    enum class Readiness { READY, NOT_DOWNLOADED, SOURCE_AWAY }
}

/**
 * The one line, decided.
 *
 * @param isOnDevice whether a copy is on this device — a download, an import, or a file in
 *   a folder the reader gave the app.
 * @param library everything the app holds, to answer whether this publication is also
 *   somewhere else. Identity is stable across sources (ADR-0006), so the same book from a
 *   folder and from a server shares an id and differs only in [Publication.sourceId].
 */
internal fun provenanceOf(
    publication: Publication,
    registry: SourceRegistry,
    isOnDevice: Boolean,
    library: List<Publication>,
): Provenance {
    // A picked folder is not a library the reader can be sent to, and neither is a source
    // the registry has forgotten: both are already here.
    val from = publication.sourceId
        ?.let { registry[it] }
        ?.takeIf { it.kind != SourceKind.LOCAL_FOLDER }
    val anotherSourceHasIt =
        library.any { it.id == publication.id && it.sourceId != publication.sourceId }
    // The union the field documents. A download whose library is still configured is in two
    // places even when the library holds exactly one row for it, and that row is the one this
    // page is *not* opening.
    val isAlsoElsewhere = anotherSourceHasIt || (isOnDevice && from != null)

    // A copy on the device, a source that is gone, a file handed over by the system, and a
    // folder the reader pointed at are the same sentence: it is here.
    //
    // **`isOnDevice` joined that list on 2026-09-05, and it is a fix.** A downloaded Kavita
    // chapter read "From Home NAS" — naming the copy the page will *not* open, while the
    // bytes it opens are on the phone and readable on a train. The delta says the line "names
    // the one this page will open", and `offline-downloads` promises the download outlives
    // everything about the server; iOS had always answered `.thisDevice` here. The library is
    // not lost, it becomes the second place — see [Provenance.isAlsoElsewhere].
    //
    // The removed-source case is the one the delta names outright — "the line says it is on
    // this device, and does not name a library that no longer exists" — and it falls out of
    // asking the registry rather than the publication, because a removed source is exactly a
    // source the registry has not got.
    if (isOnDevice || from == null) {
        return Provenance(
            place = Provenance.Place.DEVICE,
            libraryName = null,
            readiness = Provenance.Readiness.READY,
            isAlsoElsewhere = isAlsoElsewhere,
        )
    }

    val readiness =
        if (from.state.canFetch) {
            Provenance.Readiness.NOT_DOWNLOADED
        } else {
            Provenance.Readiness.SOURCE_AWAY
        }

    return Provenance(
        place = Provenance.Place.LIBRARY,
        libraryName = from.displayName,
        readiness = readiness,
        isAlsoElsewhere = isAlsoElsewhere,
    )
}

/**
 * The provenance sentence, in the reader's language.
 *
 * Composed from at most two resources rather than from eight: the base sentence answers
 * where and whether, and "also elsewhere" wraps it. Eight strings would be eight
 * translations to keep in step, and four of them would say the same thing twice.
 */
@Composable
internal fun provenanceLabel(provenance: Provenance): String {
    val name = provenance.libraryName
    val base = when {
        provenance.place == Provenance.Place.DEVICE || name == null ->
            stringResource(R.string.detail_provenance_device)

        provenance.readiness == Provenance.Readiness.NOT_DOWNLOADED ->
            stringResource(R.string.detail_provenance_not_downloaded, name)

        provenance.readiness == Provenance.Readiness.SOURCE_AWAY ->
            stringResource(R.string.detail_provenance_away, name)

        else -> stringResource(R.string.detail_provenance_library, name)
    }
    return if (provenance.isAlsoElsewhere) {
        stringResource(R.string.detail_provenance_also, base)
    } else {
        base
    }
}

/**
 * The line itself: one `bodySmall`, quiet, at the foot of the information.
 *
 * `bodySmall` rather than a label style because it is a sentence and not a chip, and
 * because the divergence register puts chrome type on Material's own scale. Read rather
 * than inferred — the delta requires availability to be *in the text*, so a screen-reader
 * user gets the same answer as a sighted one and dimming a cover elsewhere is never the
 * only way that fact is carried.
 */
@Composable
internal fun ProvenanceLine(provenance: Provenance, modifier: Modifier = Modifier) {
    val palette = LocalStoryArcPalette.current
    Text(
        text = provenanceLabel(provenance),
        style = MaterialTheme.typography.bodySmall,
        color = palette.textTertiary,
        modifier = modifier,
    )
}
