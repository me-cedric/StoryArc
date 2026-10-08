package app.storyarc.core.model

import java.text.Normalizer
import java.util.UUID

/** Why a passphrase pair cannot seal an export. */
enum class ExportPassphraseProblem {
    EMPTY,
    MISMATCH,
}

/**
 * The sealed credentials of every source that holds one, or null when none does.
 *
 * `library-portability` / *Carrying secrets under a passphrase*: each secret is written only as
 * ciphertext. The secret is read through [secretFor] at the moment of sealing and kept nowhere;
 * `:core:model` cannot see the secure store, so the caller hands the reader in. A source whose
 * handle points at nothing is skipped: it is still exported as needing a sign-in, which is the
 * truth.
 *
 * iOS's `LibraryExport.sealedSecrets` is the same rule.
 */
fun LibraryExport.sealedSecrets(
    snapshot: LibrarySnapshot,
    passphrase: String,
    secretFor: (Source) -> String?,
): LibrarySecrets? {
    val secrets = mutableMapOf<UUID, String>()
    for (source in snapshot.sources.sources) {
        if (source.credentialReference == null) continue
        secretFor(source)?.let { secrets[source.id] = it }
    }
    if (secrets.isEmpty()) return null
    return LibrarySecretSealer.seal(secrets, passphrase)
}

/** The rule for the two passphrase fields on the export sheet. */
object ExportPassphrase {

    /**
     * What is wrong with the pair, or null when it can seal an export.
     *
     * `library-portability`: "a passphrase twice that matches". An empty value is refused first,
     * because two empty fields match and seal nothing. The two are compared after NFC
     * normalisation, so one passphrase typed composed and decomposed is one passphrase, as the
     * sealer reads it.
     */
    fun problem(passphrase: String, confirmation: String): ExportPassphraseProblem? = when {
        passphrase.isEmpty() -> ExportPassphraseProblem.EMPTY
        nfc(passphrase) != nfc(confirmation) -> ExportPassphraseProblem.MISMATCH
        else -> null
    }

    private fun nfc(text: String) = Normalizer.normalize(text, Normalizer.Form.NFC)
}
