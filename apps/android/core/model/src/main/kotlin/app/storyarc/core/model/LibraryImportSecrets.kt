package app.storyarc.core.model

import java.util.UUID

/**
 * The sources whose sealed secret this import would use.
 *
 * `library-portability` / *Secrets travel only sealed, and only when asked*. A secret reaches a
 * source that exists after the merge and that this device holds no secret for. A source the
 * device is already signed in to keeps its own, for the reason an existing source is left alone:
 * the copy on this device is the one that works. A held source with no secret is filled, because
 * that is the secret the reader would be asked for.
 *
 * iOS's `LibraryImport.fillableSources` is the same rule.
 */
fun LibraryImport.fillableSources(document: LibraryDocument, device: LibrarySnapshot): Set<UUID> {
    val secrets = document.secrets ?: return emptySet()
    val sealed = secrets.sealed.keys.mapNotNull(::wireId).toSet()
    val signedIn = device.sources.sources
        .filter { it.credentialReference != null }
        .map { it.id }
        .toSet()
    val kept = document.library.sources
        .filter { wireEnumOrNull<SourceKind>(it.kind) != null }
        .mapNotNull { wireId(it.id) }
        .toSet()
    return sealed.intersect(kept) - signedIn
}

/** Whether the reader has to give a passphrase for this import to carry its secrets. */
fun LibraryImport.needsPassphrase(document: LibraryDocument, device: LibrarySnapshot): Boolean =
    fillableSources(document, device).isNotEmpty()

/**
 * The merge, with opened secrets given to the sources they belong to.
 *
 * Each filled source gets the handle [reference] names, and the result lists those sources in
 * [LibraryImportResult.credentialed] so the caller writes the secrets to the secure store. A
 * source given a secret is no longer listed as needing a sign-in.
 *
 * @param secrets opened secrets by source id. Ids this import cannot use are ignored.
 * @param reference the handle the secure store files a source's secret under.
 */
fun LibraryImport.merging(
    document: LibraryDocument,
    device: LibrarySnapshot,
    secrets: Map<UUID, String>,
    reference: (UUID) -> String,
): LibraryImportResult {
    val merged = merging(document, device)
    val fill = fillableSources(document, device).intersect(secrets.keys)
    var registry = merged.snapshot.sources
    val credentialed = mutableSetOf<UUID>()
    for (id in fill) {
        val source = registry.sources.firstOrNull { it.id == id } ?: continue
        registry = registry.replacing(source.copy(credentialReference = reference(id)))
        credentialed += id
    }
    return merged.copy(
        snapshot = merged.snapshot.copy(sources = registry),
        credentialed = credentialed,
        sourcesNeedingSignIn = signInsNeeded(document, device, credentialed),
    )
}
