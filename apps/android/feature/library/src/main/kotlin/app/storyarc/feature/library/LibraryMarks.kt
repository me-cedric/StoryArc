package app.storyarc.feature.library

import app.storyarc.core.model.Publication
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceKind
import app.storyarc.core.model.SourceRegistry
import java.io.File

/**
 * The two things a cover is allowed to say besides how far the reader got.
 *
 * `library-browsing` caps a cover at two marks — "how far the reader has got, and whether it
 * can be read with no network" — and forbids a third "for any reason". Both of the rules
 * here decide the second one, from opposite ends: [isKeptOnDevice] draws a mark and
 * [isReadableNow] takes brightness away. Neither ever removes a publication from the shelf,
 * which is the distinction the requirement turns on: "a library that shrinks when the Wi-Fi
 * drops reads as data loss".
 *
 * Pure and free of Compose, because a rule asked once per visible cell on every redraw is
 * worth asserting directly rather than reading off a screenshot. iOS keeps the same two rules
 * in the same shape — `LibraryModel.isOnDevice` and `LibraryAvailability.isReadableNow`.
 */

/**
 * How dim a publication that cannot be opened right now is drawn.
 *
 * One number for the home surface and the library shelf alike. Two of them would be two
 * answers to "how far down is away", and a reader moving between the two screens would see
 * the same book at two brightnesses.
 */
internal const val AWAY_ALPHA = 0.45f

/**
 * Whether a publication's bytes are on this device at all.
 *
 * A path or a document URI is; a share is not. `network-share` locations are written as
 * `smb://…` and an online library's as `http(s)://…`, and a shared folder is precisely the
 * thing that stops working on a plane.
 *
 * Written as a scheme test rather than asked of `PublicationAccess`, whose `isRemote` answers
 * from a table the app layer fills in at start-up: a rule that is true or false depending on
 * how far the app has booted is not a rule a shelf can draw from, and not one a host test can
 * assert. The on-device destination has asked this question this way since it was written;
 * this is the same function, moved next to the two rules that now also need it.
 */
fun isOnDevice(location: String?): Boolean = when {
    location.isNullOrEmpty() -> false
    location.startsWith("/") -> true
    location.startsWith("file://") -> true
    location.startsWith("content://") -> true
    else -> false
}

/**
 * Whether the app's own copy of this publication is on the device.
 *
 * A path comparison against the download store's own directory, which is the answer iOS
 * gives and gives for the same reason: a publication found by a folder scan is on the device
 * too, but not *kept* by the app — the card can be pulled, the grant can lapse, the folder
 * can be unmounted, and `LibraryScreen`'s unavailable-folders notice exists because that
 * happens. Only a copy in the app's own storage carries `offline-downloads`' promise, so only
 * that copy earns `design.md`'s "small filled mark in one corner".
 *
 * The separator is appended to the folder before the comparison, so a sibling directory whose
 * name merely begins with the store's — `…/downloads-old` beside `…/downloads` — is not read
 * as being inside it.
 *
 * @param downloads the download store's directory, or null on a view model built without one.
 */
internal fun isKeptOnDevice(location: String?, downloads: File?): Boolean {
    if (location.isNullOrEmpty() || downloads == null) return false
    val folder = downloads.absolutePath
    val prefix = if (folder.endsWith(File.separator)) folder else folder + File.separator
    return location.startsWith(prefix)
}

/**
 * Whether a publication can be opened at this instant.
 *
 * `library-browsing`: one that is neither on the device nor currently reachable "is dimmed
 * and still selectable, so it can be inspected, downloaded later, or added to a shelf", and
 * "dimming is the only difference — it is not moved, grouped apart, or badged as an error".
 * So this decides an opacity and never a filter.
 *
 * Three answers, in the order they are asked:
 *
 * 1. **The bytes are local.** A file, a document the reader picked, a finished download —
 *    none of them needs a network. The one exception is the case Android has and iOS does
 *    not: a picked folder whose persisted grant the system no longer honours. Its files are
 *    still on the device and the app may no longer read them, so the source's own state has
 *    the last word. `LibraryAvailability.isReadableOffline` files that under the same rule.
 * 2. **No library claims it.** Readable by definition: it came from a file another app handed
 *    over, and attributing it to whichever library happens to be down would be a guess that
 *    dimmed it for nothing.
 * 3. **Everything else has to be fetched**, so its library has to be answering.
 *
 * *Connecting* is not a verdict, which is the one place this deliberately does not use
 * `SourceConnectionState.canFetch`. Every network source is probed when the library appears,
 * so treating "still asking" as "cannot be reached" would grey the whole shelf on every
 * launch and un-grey it a second later — a flash that tells the reader their library is
 * broken and then that it is not. iOS's rule says so in as many words.
 *
 * The format is deliberately not consulted. A publication no decoder will open is a different
 * message, and the cell already carries it as a caption; dimming it as well would conflate
 * "your network is down" with "this file is a CB7".
 */
internal fun isReadableNow(
    publication: Publication,
    location: String?,
    registry: SourceRegistry,
): Boolean {
    val source = publication.sourceId?.let { registry[it] }
    if (isOnDevice(location)) {
        if (source == null || source.kind != SourceKind.LOCAL_FOLDER) return true
        return source.state.isAnswering
    }
    return source == null || source.state.isAnswering
}

/**
 * Whether a source is answering, or has not been asked yet.
 *
 * Not `canFetch`, which is `Connected` alone. See [isReadableNow] for why the difference
 * matters on every launch.
 */
private val SourceConnectionState.isAnswering: Boolean
    get() = this is SourceConnectionState.Connected || this is SourceConnectionState.Connecting
