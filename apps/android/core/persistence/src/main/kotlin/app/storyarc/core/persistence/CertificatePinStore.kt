package app.storyarc.core.persistence

import android.content.Context
import android.content.SharedPreferences

/**
 * The certificates a reader has explicitly accepted, on disk.
 *
 * `opds-catalog` lets a reader pin a self-signed certificate "after showing its fingerprint
 * and an explicit warning". A pin that did not survive a launch would ask that question
 * every morning, and a question asked daily is a question answered without reading it --
 * which is the failure mode the warning exists to prevent.
 *
 * Ordinary preferences, not the keystore. A fingerprint is a public value: it is printed by
 * `openssl`, sent by the server to anyone who connects, and useless to an attacker who does
 * not already control the connection. What it must be is *hard to change quietly*, and an
 * app's own preferences are as private as its keystore is to anything but this app.
 *
 * iOS's `CertificatePinStore` is the same four operations against `UserDefaults`.
 */
class CertificatePinStore internal constructor(private val preferences: SharedPreferences) {

    companion object {
        private const val NAME = "app.storyarc.certificatePins"

        fun open(context: Context): CertificatePinStore =
            CertificatePinStore(context.getSharedPreferences(NAME, Context.MODE_PRIVATE))
    }

    /** Every accepted fingerprint, per host. */
    fun pins(): Map<String, Set<String>> = preferences.all.entries
        .mapNotNull { (host, value) ->
            @Suppress("UNCHECKED_CAST")
            (value as? Set<String>)?.let { host to it }
        }
        .toMap()

    fun save(pins: Map<String, Set<String>>) {
        val editor = preferences.edit()
        editor.clear()
        pins.forEach { (host, fingerprints) -> editor.putStringSet(host, fingerprints) }
        editor.apply()
    }

    /**
     * Forgets one host's pins. Called when its source is removed, so re-adding the same
     * server asks the question again rather than trusting a decision the reader
     * deliberately undid.
     */
    fun forget(host: String) {
        preferences.edit().remove(host).apply()
    }

    fun reset() {
        preferences.edit().clear().apply()
    }
}
