package app.storyarc.core.model

import kotlinx.serialization.Serializable

/**
 * The reader's library, in one versioned JSON document they can open.
 *
 * `library-portability` / *One versioned document*: an export "declares a format version, the
 * app version and the platform that wrote it, and the moment it was written", and the body is
 * "readable JSON, so a reader can open it and a later version can diff it".
 *
 * **This type is the wire, not a store.** design.md settles that the two platforms keep their
 * own stores and reconcile here instead, because changing a store to agree is a migration on
 * every existing install to fix a divergence only the export can see. So the five records the
 * two platforms spell differently — the source timestamp, the source kind, the shelf cover
 * key, the reading position and the pinned-shelf container — take the shape below, and each
 * platform converts at its own boundary.
 *
 * **The document spells an enum case in lower camel**, which is what Swift's raw values
 * already are. Every enum crossing this boundary is therefore a `String` here and goes
 * through [wireCase], rather than through `kotlinx`'s own name. iOS's `LibraryDocument`
 * carries the same fields.
 */
@Serializable
data class LibraryDocument(
    val formatVersion: Int = CURRENT_FORMAT_VERSION,
    val appVersion: String,
    val writtenBy: String,
    /** ISO 8601, to whole seconds. See [wireMoment]. */
    val writtenAt: String,
    val library: LibraryBody = LibraryBody(),
    /**
     * Reserved, and never filled by this writer.
     *
     * The owner asked for credentials to travel encrypted under a passphrase. Two standing
     * rules forbid it and both name backups by name: the `sources` capability's *Credential
     * storage* requirement, and `AGENTS.md` non-negotiable 4. An encrypted secret in a file
     * is still a secret in a file, so turning this on is an amendment the owner makes
     * knowingly rather than a thing an unrelated change slips in.
     *
     * The field exists so that saying yes later is one change and no rework: fill it, and
     * amend the two rules. design.md fixes the crypto — PBKDF2-HMAC-SHA256, AES-256-GCM,
     * every parameter in the document — so the decision is a yes or a no.
     */
    val secrets: LibrarySecrets? = null,
) {
    companion object {
        /**
         * The newest format this build writes, and the newest it can read.
         *
         * One is the first. design.md: the transform chain exists from the start with
         * nothing in it, so the second version has somewhere to go.
         */
        const val CURRENT_FORMAT_VERSION = 1

        /** What [writtenBy] says on this platform. iOS writes `ios`. */
        const val THIS_PLATFORM = "android"
    }
}

/**
 * The passphrase-encrypted credential block, which this writer never produces.
 *
 * Its parameters are all in the document on purpose: a hard-coded iteration count cannot be
 * raised later without breaking every file already written. See [LibraryDocument.secrets].
 */
@Serializable
data class LibrarySecrets(
    val kdf: String,
    val iterations: Int,
    val salt: String,
    val cipher: String,
    val nonce: String,
    val ciphertext: String,
)

/**
 * Everything the export carries.
 *
 * `library-portability` / *The library's shape* names the list: "the sources and servers, the
 * collections and reading lists, the pinned shelves, the settings, the reading themes, the
 * per-publication reader settings, the reading progress, and the covers the reader chose".
 * The last of those is a member identifier rather than an image — a shelf's chosen cover
 * names one of its own members — so it travels inside the shelf that chose it.
 */
@Serializable
data class LibraryBody(
    val sources: List<DocumentSource> = emptyList(),
    /**
     * Accepted certificate fingerprints, per host.
     *
     * Carried because a reader who accepted a self-signed certificate on one device should
     * not have to read the same fingerprint off the same server again.
     * `library-portability` requires the import to say "which source gained a pin and from
     * where" rather than changing what the app trusts without a word.
     */
    val certificatePins: Map<String, List<String>> = emptyMap(),
    val collections: List<DocumentCollection> = emptyList(),
    val readingLists: List<DocumentReadingList> = emptyList(),
    /**
     * Pinned shelves as a list of `ShelfPin` tokens.
     *
     * The token spelling is already shared; the container is not. iOS keeps one
     * space-separated scalar because `@AppStorage` stores scalars, and this platform keeps a
     * string set because its preferences take one natively. A list is the shape both can
     * write without either having to change how it stores them.
     */
    val pinnedShelves: List<String> = emptyList(),
    val settings: DocumentSettings = DocumentSettings(),
    val readingThemes: DocumentThemes = DocumentThemes(),
    val progress: List<DocumentProgress> = emptyList(),
    /**
     * The covers the reader chose, each filed under the key the cover store uses.
     *
     * Images in base64, because a chosen cover has no other source: a publication's own cover
     * is read from the publication, and the cover cache is recreated.
     */
    val covers: List<DocumentCover> = emptyList(),
)

/**
 * A source, without its secret.
 *
 * `library-portability` / *A server in the export*: "its address, its name, its username and
 * its settings travel, and its secret does not". [Source.credentialReference] is a handle
 * into this device's secure store and means nothing on another device, so it does not travel
 * either — [needsSignIn] carries the one fact the other device needs from it.
 */
@Serializable
data class DocumentSource(
    val id: String,
    val displayName: String,
    /** The kind in lower camel: `localFolder`, not `LOCAL_FOLDER`. */
    val kind: String,
    /**
     * When this source last answered, as ISO 8601. This platform keeps epoch millis and iOS
     * keeps a `Date`; neither spelling is readable in a file, and one of them is not even a
     * date.
     */
    val lastSuccessfulSync: String? = null,
    val locator: String? = null,
    /**
     * Whether the source held a secret on the device that wrote the document.
     *
     * The secret itself never travels, so this is how the importing device knows to list the
     * source as needing a sign-in rather than as simply unreachable.
     */
    val needsSignIn: Boolean = false,
)

/**
 * A collection, with the cover its reader chose.
 *
 * `coverMemberId`, with a lower-case `d`. iOS stores `coverMemberID` and this platform
 * `coverMemberId`; one of the two had to give, and the document takes this one because JSON
 * keys elsewhere in it are lower camel throughout.
 */
@Serializable
data class DocumentCollection(
    val id: String,
    val name: String,
    val members: List<String> = emptyList(),
    val coverMemberId: String? = null,
)

/**
 * A reading list, with the cover its reader chose. Ordered, which is its whole difference
 * from a collection.
 */
@Serializable
data class DocumentReadingList(
    val id: String,
    val name: String,
    val entries: List<String> = emptyList(),
    val coverMemberId: String? = null,
)

/**
 * The reading themes and the per-publication reader settings, which are one store.
 *
 * A list of entries rather than the two keyed maps [ShelfMemory] holds, because those keys
 * are built from a scope's own name and the two platforms spell a scope differently — so a
 * map carried verbatim would lose every per-series choice the moment it crossed. An entry
 * with no [DocumentThemeEntry.shelf] is a scope's default.
 */
@Serializable
data class DocumentThemes(
    val entries: List<DocumentThemeEntry> = emptyList(),
    val customPalette: ReaderPalette? = null,
)

/** One remembered reading setup: a scope's default, or one shelf's own choice. */
@Serializable
data class DocumentThemeEntry(
    val scope: String,
    val shelf: String? = null,
    val settings: DocumentShelfSettings = DocumentShelfSettings(),
)

/**
 * One reading position, with the watermark deliberately left behind.
 *
 * [ReadingProgress.syncedPosition] records what *this* device last exchanged with a server.
 * It is a fact about one device's conversation, not about the reader's library, and carrying
 * it would tell the importing device it had synchronised when it never had. An imported
 * record therefore arrives with no watermark, which is exactly the case [ProgressMerge] was
 * fixed to read correctly — task 1.4 is a prerequisite for this type.
 */
@Serializable
data class DocumentProgress(
    val identity: DocumentIdentity,
    val position: DocumentPosition,
    val isFinished: Boolean = false,
    val finishedAt: String? = null,
    val updatedAt: String,
)
