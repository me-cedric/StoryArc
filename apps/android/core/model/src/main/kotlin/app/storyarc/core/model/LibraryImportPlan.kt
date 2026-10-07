package app.storyarc.core.model

/**
 * What an import is about to do, before it does any of it.
 *
 * `library-portability` / *The reader sees what will happen first*: "the app states what it
 * will add, what it will merge, and what it will ask for a sign-in, before anything changes".
 * Counts and names rather than sentences, because the sentences are four languages' business
 * and this has to be the same value on both platforms.
 *
 * iOS's `LibraryImportPlan` carries the same fields.
 */
data class LibraryImportPlan(
    /** Sources the device does not have, by the name the document gives them. */
    val sourcesToAdd: List<String> = emptyList(),
    /**
     * Sources that will arrive without their secret, by name.
     *
     * A subset of [sourcesToAdd] plus any already-known source whose secret this device
     * lacks. `library-portability`: the source "is listed, marked as needing a sign-in, and
     * reaching it asks for the secret once".
     */
    val sourcesNeedingSignIn: List<String> = emptyList(),
    /** Collections and reading lists the device does not have, by name. */
    val shelvesToAdd: List<String> = emptyList(),
    /**
     * Shelves that exist on both sides, with how many members the import adds to each.
     *
     * `library-portability`: "their members are merged rather than one replacing the other,
     * and the reader is told how many were added".
     */
    val shelvesToMerge: List<ImportedShelf> = emptyList(),
    /** Publications whose position the device does not hold yet. */
    val progressToAdd: Int = 0,
    /** Publications where both sides hold a position, so [ProgressMerge] decides. */
    val progressToMerge: Int = 0,
    /**
     * Hosts that will gain a pinned certificate, and the source each pin arrives with.
     *
     * `library-portability`: "importing it does not silently change what the app trusts: the
     * reader is told which source gained a pin and from where".
     */
    val certificatePinsToAdd: List<CertificatePinNotice> = emptyList(),
    /** Whether the document's settings differ from the device's. */
    val settingsWillChange: Boolean = false,
    /** Reading themes and per-publication reader settings the device does not hold. */
    val themeEntriesToAdd: Int = 0,
    /** Chosen covers the device does not hold, and that arrive as readable images. */
    val coversToAdd: Int = 0,
)

/** One shelf that exists on both sides. */
data class ImportedShelf(val name: String, val membersAdded: Int)

/**
 * One host about to gain a pinned certificate, and the source it arrived with.
 *
 * [sourceName] is null when no source in the document points at the host — a pin can outlive
 * the source that accepted it, and a pin with no source is still a change to what the app
 * trusts and still has to be named.
 */
data class CertificatePinNotice(val host: String, val sourceName: String?)
