package app.storyarc.feature.library

import app.storyarc.core.catalogue.CertificatePins
import app.storyarc.core.catalogue.OpdsOrigin
import app.storyarc.core.model.Source
import app.storyarc.core.persistence.CertificatePinStore

/**
 * Forgets a removed source's certificate pin, unless another saved source still answers at
 * the same host.
 *
 * 11.9: `CertificatePins.forget` and `CertificatePinStore.forget` are documented as "called
 * when its source is removed", and nothing called either of them -- removing a pinned
 * catalogue or Kavita server left its pin on both the running app and the disk, so re-adding
 * a different server at the same host silently inherited a trust decision this reader never
 * made about it.
 *
 * Its own file rather than a line inside [LibraryViewModel.removeSource]: that file is at
 * the length the line cap records for it.
 */
fun LibraryViewModel.forgetPinIfUnshared(
    source: Source,
    pins: CertificatePins,
    pinStore: CertificatePinStore?,
) {
    val host = source.locator?.let(OpdsOrigin::of)?.host ?: return
    val sharedWithAnotherSource = _registry.value.sources.any {
        it.id != source.id && it.locator?.let(OpdsOrigin::of)?.host == host
    }
    if (sharedWithAnotherSource) return
    pins.forget(host)
    pinStore?.forget(host)
}
