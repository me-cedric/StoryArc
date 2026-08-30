package app.storyarc.feature.library

import app.storyarc.core.catalogue.OpdsDocument
import app.storyarc.core.kavita.KavitaAddress
import java.net.URI

/**
 * What the reader pasted into "Add catalogue", once it has been recognised.
 *
 * Kavita's OPDS URL is `https://host/api/opds/<key>`, and that key is the reader's own
 * full-privilege API key — the one that mints session tokens. Pasted into the generic
 * catalogue sheet it used to be treated as any other feed: the fetch succeeded because the
 * path *is* the credential, nothing ever asked for a secret, and the whole key-bearing URL
 * was written into the registry — which is `SharedPreferences`, in the clear, and rides
 * along in Google cloud backup and device-to-device transfer. `sources` forbids a secret
 * reaching preferences or backups, and `kavita-server` asks for such a paste to configure
 * "a native Kavita source rather than a generic OPDS source". Nothing in that sentence says
 * which sheet it was pasted into.
 *
 * Recognition is a value rather than a branch inside the connection, so what the app does
 * with an address can be asserted without a server. iOS's `CatalogueTarget` answers the same
 * three ways.
 */
internal sealed interface CatalogueTarget {

    /** A Kavita server, with the key already taken out of the address. */
    data class Kavita(val address: KavitaAddress) : CatalogueTarget

    /** A feed to fetch. */
    data class Feed(val url: String) : CatalogueTarget

    /** Not an address at all. */
    data object Unusable : CatalogueTarget

    companion object {
        /**
         * Kavita first, always.
         *
         * Order is the whole point: `OpdsDocument.address` completes a Kavita OPDS URL into
         * a perfectly good feed URL, so anything that asks it first has already lost the key
         * into the catalogue flow.
         */
        fun of(typed: String): CatalogueTarget {
            KavitaAddress.fromOpds(typed)?.let { return Kavita(it) }
            val url = OpdsDocument.address(typed) ?: return Unusable
            return Feed(url)
        }

        /**
         * The locator a registry entry may hold for a feed.
         *
         * The registry is preferences, so a locator is a string the reader's backup carries
         * in the clear. `https://user:password@host/feed` is a working credential written as
         * an address, and `HttpURLConnection` authenticates from it — so the caller moves it
         * into the secure store and saves what this returns, which is the same address with
         * the secret taken out of it.
         */
        fun storableLocator(url: String): String {
            val uri = runCatching { URI(url) }.getOrNull() ?: return url
            if (uri.userInfo.isNullOrEmpty()) return url
            return runCatching {
                URI(uri.scheme, null, uri.host, uri.port, uri.path, uri.query, uri.fragment)
                    .toString()
            }.getOrDefault(url)
        }

        /**
         * The credential a URL carries in itself, if it carries one.
         *
         * Null for an ordinary address. Present for `user:password@host`, which is the case
         * that reached the registry as plaintext: the fetch succeeded on it, so it is a
         * working secret and belongs in the secure store rather than in the locator.
         */
        fun embeddedCredential(url: String): Pair<String, String>? {
            val info = runCatching { URI(url) }.getOrNull()?.userInfo
            if (info.isNullOrEmpty()) return null
            val user = info.substringBefore(':')
            if (user.isEmpty()) return null
            return user to info.substringAfter(':', "")
        }
    }
}
