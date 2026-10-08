package app.storyarc.feature.library

import androidx.compose.foundation.layout.Column
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.semantics
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.model.Publication
import app.storyarc.core.model.SourceConnectionState
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
     * The reader's own name for the other place this publication is, or null when it is in no
     * other place the reader can be told about.
     *
     * The delta: "the line names the one this page will open, and says the publication is
     * also available elsewhere". Without it, a reader who owns the same volume locally and
     * on a server cannot tell which one they are about to read — which is the exact failure
     * taking origin off the shelf would otherwise cause.
     *
     * **Named, since one-vocabulary 4.6 / O19.** iOS has always named the second place and this
     * platform said only *also elsewhere in your library*. A second copy whose library the
     * registry no longer holds has no name to give, so it is not claimed — the rule iOS's
     * `alsoHolding` has always applied.
     *
     * **Two ways a second place arises.** A copy on the device whose library still exists —
     * the server it was fetched from is the other place, and the library a download came from
     * wins, because it is the place the reader chose — and another source in the library
     * holding the same publication. Identity is stable across sources (ADR-0006), so the
     * second is answerable by id.
     */
    val alsoIn: String?,
) {
    /**
     * Where a publication lives. A library the reader added, this device, or nowhere the
     * reader can name: its source is gone and no copy is here, which iOS says in the same
     * words (`detail.provenance.unattributed`).
     */
    enum class Place { DEVICE, LIBRARY, UNATTRIBUTED }

    /**
     * Whether it can be opened right now, which the same line has to answer.
     *
     * [READY] is silent rather than reassuring: a line that says "ready to read" on every
     * publication a reader owns is a line they stop reading, and then it cannot warn them.
     *
     * **[SOURCE_AWAY] is for a source that is not answering, and not for one nobody has
     * asked.** Connection state is never persisted, so every source loads as *connecting* and
     * stays there until something probes it — and this read `canFetch`, which is `Connected`
     * alone, so the line claimed a failed probe for all of that time. Measured on an emulator
     * on 2026-09-11: a catalogue that `curl` answered with 200, and that the shelf had just
     * read nine titles from, read *From Attic Catalogue — not answering right now* for as
     * long as the page was open, while *Your libraries* read *Available* for the same source
     * on the same device. iOS never had the defect — `PublicationProvenance.swift` asks
     * `if case .unreachable` and nothing else — so this is also the two platforms agreeing
     * again.
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
    // The first other copy whose library the registry still holds, in library order, which is
    // iOS's `alsoHolding` rule. A picked folder is not a library the reader can be sent to, so
    // it is not named as one either.
    val otherLibrary = library
        .asSequence()
        .filter { it.id == publication.id && it.sourceId != publication.sourceId }
        .mapNotNull { other -> other.sourceId?.let { registry[it] } }
        .firstOrNull { it.kind != SourceKind.LOCAL_FOLDER }
        ?.displayName
    // The library a download came from wins: it is the place the reader chose, and a
    // coincidence of identity on the shelf is not. See [Provenance.alsoIn].
    val alsoIn = if (isOnDevice) from?.displayName ?: otherLibrary else otherLibrary

    // A copy on the device, a source that is gone, a file handed over by the system, and a
    // folder the reader pointed at are the same sentence: it is here.
    //
    // **`isOnDevice` joined that list on 2026-09-05, and it is a fix.** A downloaded Kavita
    // chapter read "From Home NAS" — naming the copy the page will *not* open, while the
    // bytes it opens are on the phone and readable on a train. The delta says the line "names
    // the one this page will open", and `offline-downloads` promises the download outlives
    // everything about the server; iOS had always answered `.thisDevice` here. The library is
    // not lost, it becomes the second place — see [Provenance.alsoIn].
    //
    // The removed-source case is the one the delta names outright — "the line says it is on
    // this device, and does not name a library that no longer exists" — and it falls out of
    // asking the registry rather than the publication, because a removed source is exactly a
    // source the registry has not got.
    //
    // **No copy here and no library to name is the one place nothing can be said about.** The
    // source was removed, or the publication never had one, and the bytes are not on the device.
    // Saying *on this device* there was false; iOS says *not in a library you added* and so
    // does this now (`PublicationProvenance.of`, `.unattributed`). A picked folder is not this
    // case: the registry still holds it, so the line stays the device sentence.
    val sourceIsGone = publication.sourceId?.let { registry[it] } == null
    if (!isOnDevice && sourceIsGone) {
        return Provenance(
            place = Provenance.Place.UNATTRIBUTED,
            libraryName = null,
            readiness = Provenance.Readiness.NOT_DOWNLOADED,
            alsoIn = alsoIn,
        )
    }
    if (isOnDevice || from == null) {
        return Provenance(
            place = Provenance.Place.DEVICE,
            libraryName = null,
            readiness = Provenance.Readiness.READY,
            alsoIn = alsoIn,
        )
    }

    // Asked of the one state that means it, rather than of `canFetch`, which is `Connected`
    // alone and made *connecting* read as *not answering*. The bytes are not here either way,
    // so a source nobody has probed yet gets the true half of the sentence and no claim about
    // the network. iOS asks the same question in the same words — `if case .unreachable`.
    val readiness = if (from.state is SourceConnectionState.Unreachable) {
        Provenance.Readiness.SOURCE_AWAY
    } else {
        Provenance.Readiness.NOT_DOWNLOADED
    }

    return Provenance(
        place = Provenance.Place.LIBRARY,
        libraryName = from.displayName,
        readiness = readiness,
        alsoIn = alsoIn,
    )
}

/**
 * The provenance sentence, in the reader's language: one whole sentence per state.
 *
 * **One string per state, never a clause joined to a clause** (one-vocabulary 4.6, O19).
 * French, German and Spanish order the words of *from X, not on this device* differently from
 * English, so a place string and an availability string joined by a comma is a sentence only
 * English can write. The five sentences below each carry their own words and take at most the
 * library's name.
 */
@Composable
internal fun provenanceLabel(provenance: Provenance): String {
    val name = provenance.libraryName
    return when {
        provenance.place == Provenance.Place.UNATTRIBUTED ->
            stringResource(R.string.detail_provenance_unattributed)

        provenance.place == Provenance.Place.DEVICE || name == null ->
            stringResource(R.string.detail_provenance_device)

        provenance.readiness == Provenance.Readiness.NOT_DOWNLOADED ->
            stringResource(R.string.detail_provenance_not_here, name)

        provenance.readiness == Provenance.Readiness.SOURCE_AWAY ->
            stringResource(R.string.detail_provenance_away, name)

        else -> stringResource(R.string.detail_provenance_library, name)
    }
}

/** The second place, as a sentence of its own that names it, or null when there is none. */
@Composable
internal fun provenanceAlsoIn(provenance: Provenance): String? =
    provenance.alsoIn?.let { stringResource(R.string.detail_provenance_also_in, it) }

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
    val style = MaterialTheme.typography.bodySmall
    // Two whole sentences read as one stop, as iOS's two lines do.
    Column(modifier = modifier.semantics(mergeDescendants = true) {}) {
        Text(text = provenanceLabel(provenance), style = style, color = palette.textTertiary)
        provenanceAlsoIn(provenance)?.let {
            Text(text = it, style = style, color = palette.textTertiary)
        }
    }
}
