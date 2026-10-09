package app.storyarc.core.model

/**
 * Sources that a library sync brought from another device.
 *
 * `library-sync` task 5.8. The sync document carries every source of the reader, and some of
 * them only work on the device that added them: a folder that device picked, or an address such
 * as `127.0.0.1` that names that device itself. Such a source is marked, so the reader sees
 * where it came from, and a loopback address from it is never tried here: on this device it
 * names this device, not the server the reader added.
 */
object OtherDevice {

    /** [merged], with each source that [local] did not hold marked as from another device. */
    fun marking(merged: SourceRegistry, local: SourceRegistry): SourceRegistry = merged.copy(
        sources = merged.sources.map { source ->
            if (local[source.id] == null) source.copy(fromAnotherDevice = true) else source
        },
    )

    /** Whether [locator] names the device it is used on: `localhost`, `127.x.x.x` or `::1`. */
    fun isLoopback(locator: String?): Boolean {
        val host = host(locator ?: return false).lowercase()
        return host == "localhost" || host == "::1" || host.startsWith("127.")
    }

    /** The host of a `scheme://user@host:port/path` locator. */
    private fun host(locator: String): String {
        val authority = locator.substringAfter("://").substringBefore('/').substringAfterLast('@')
        return if (authority.startsWith("[")) {
            authority.substringAfter('[').substringBefore(']')
        } else {
            authority.substringBefore(':')
        }
    }
}

/**
 * Whether this source is from another device and its address names that device. Nothing on
 * this device tries to reach it.
 */
val Source.reachesOnlyAnotherDevice: Boolean
    get() = fromAnotherDevice && OtherDevice.isLoopback(locator)
