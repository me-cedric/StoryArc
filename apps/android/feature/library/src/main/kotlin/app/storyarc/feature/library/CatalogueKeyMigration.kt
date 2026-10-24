package app.storyarc.feature.library

import app.storyarc.core.catalogue.OpdsCredential
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
import app.storyarc.core.persistence.CredentialStore
import app.storyarc.core.persistence.SourceSecretStore
import app.storyarc.core.persistence.SourceStore

/**
 * Moves a feed key out of a catalogue row that a version before 2026-10-24 saved.
 *
 * Such a row holds `?apikey=...` (or `user:password@`) in its locator, which is preferences in
 * the clear. This moves the secret into the secure store in the format [CatalogueConnection]
 * writes, merged with a sign-in that is already there, and saves the locator without it. A row
 * with no secret is left alone, so each launch after the first changes nothing. A row whose
 * secret the store does not accept is also left alone: the key stays where it was rather than
 * being lost. A tombstone of a catalogue loses its key, because its secret was removed with it.
 */
fun SourceStore.movingCatalogueKeys(credentials: SourceSecretStore?) {
    val registry = registry()
    val migrated = registry.copy(
        sources = registry.sources.map { it.withKeyMoved(credentials) ?: it },
        tombstones = registry.tombstones.map {
            if (it.kind != SourceKind.OPDS_CATALOG) it
            else it.copy(locator = it.locator?.let(CatalogueTarget::storableLocator))
        },
    )
    if (migrated != registry) save(migrated)
}

/** This row without its secret, or null when there is none or the store refused it. */
private fun Source.withKeyMoved(credentials: SourceSecretStore?): Source? {
    if (kind != SourceKind.OPDS_CATALOG) return null
    val url = locator ?: return null
    val query = CatalogueTarget.secretQuery(url)
    val embedded = CatalogueTarget.embeddedCredential(url)
    if (query == null && embedded == null) return null
    if (credentials == null) return null
    val reference = credentialReference ?: CredentialStore.reference(id)
    val held = credentials.secret(reference)
    // A sign-in already stored wins over one in the address, as it does when a source is saved.
    val credential = held?.let(OpdsCredential::of)
        ?: embedded?.let { (user, password) -> OpdsCredential.Basic(user, password) }
    // Distinct, so a run stopped between the two writes does not store the key twice.
    val merged = listOfNotNull(held?.let(OpdsCredential::query), query)
        .flatMap { it.split('&') }
        .distinct()
        .joinToString("&")
    val secret = OpdsCredential.stored(credential, merged) ?: return null
    if (!credentials.save(secret, reference)) return null
    return copy(credentialReference = reference, locator = CatalogueTarget.storableLocator(url))
}
