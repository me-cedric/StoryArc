package app.storyarc.core.model

/**
 * One field a sync merges on its own: its name in the document, how to read it, and how to
 * take it from another value.
 *
 * `library-sync` task 3.5: settings and themes merge last-writer-wins *per field*, so one
 * device's theme and another device's font size both survive. iOS's `SyncField` lists the same
 * names, and the cross-platform documents fail if the two lists drift.
 */
class SyncField<T>(
    val name: String,
    val read: (T) -> Any?,
    val take: (into: T, from: T) -> T,
)

/** A value after a field merge, with the moment each field last changed. */
data class StampedValue<T>(val value: T, val changedAt: Map<String, Long>)

/**
 * The moments a field changed: stamped by a store when the reader changes it, and compared
 * between two devices when a sync merges.
 *
 * Moments are compared to the whole second, because the document writes them to the whole
 * second (see [wireMoment]). A moment this device holds to the millisecond would otherwise read
 * as newer than the same moment read back from the document.
 */
object ChangeStamps {

    /**
     * The moment a field counts as changed when nothing stamped it and it is not the default:
     * changed before sync existed. One second, so it wins over a default and loses to any real
     * stamp.
     */
    const val UNKNOWN_CHANGE = 1_000L

    /** [epochMillis] to the whole second, the resolution of the document. */
    fun seconds(epochMillis: Long): Long = Math.floorDiv(epochMillis, 1_000L) * 1_000L

    /**
     * The moments a store writes with [after].
     *
     * A field whose value changed while its moment did not is a change the reader made, so it
     * is stamped [now]. A field whose moment the caller changed keeps that moment. A sync does
     * not come here: it writes the moments its merge decided as they are, because a value the
     * merge took from another device is not a change this device made.
     *
     * @param before the values held now, by field name.
     * @param after the values about to be written.
     * @param default the value of a field missing on one side: a theme entry that is not there
     *   reads as the defaults, so creating one stamps only the fields that differ from them, and
     *   removing one stamps the fields it had changed.
     */
    fun restamped(
        before: Map<String, Any?>,
        beforeStamps: Map<String, Long>,
        after: Map<String, Any?>,
        afterStamps: Map<String, Long>,
        now: Long,
        default: (String) -> Any? = { null },
    ): Map<String, Long> {
        val changed = (before.keys + after.keys).filter { key ->
            val was = if (before.containsKey(key)) before[key] else default(key)
            val becomes = if (after.containsKey(key)) after[key] else default(key)
            was != becomes && afterStamps[key] == beforeStamps[key]
        }
        return afterStamps + changed.associateWith { now }
    }

    /**
     * Last writer wins, field by field.
     *
     * The newer moment takes the field. On the same second with two values, the device whose id
     * sorts last wins, so two devices settle on one value instead of each keeping its own. A
     * field the other side cannot express keeps this device's value: each [SyncField.take]
     * decides that for its own field.
     *
     * @param key the name a field's moment is filed under, for a field inside an entry.
     */
    fun <T> merging(
        fields: List<SyncField<T>>,
        default: T,
        local: T,
        localStamps: Map<String, Long>,
        remote: T,
        remoteStamps: Map<String, DocumentStamp>,
        device: String,
        key: (String) -> String = { it },
    ): StampedValue<T> {
        var value = local
        val stamps = mutableMapOf<String, Long>()
        for (field in fields) {
            val name = key(field.name)
            val mine = localStamps[name]?.let(::seconds) ?: unknown(field, local, default)
            val theirs = remoteStamps[name]
            val theirsAt = epochMillis(theirs?.at) ?: unknown(field, remote, default)
            val differ = field.read(local) != field.read(remote)
            val remoteWins = theirsAt > mine ||
                (theirsAt == mine && theirsAt > 0 && differ && (theirs?.by ?: "") > device)
            if (remoteWins) {
                value = field.take(value, remote)
                stamps[name] = theirsAt
            } else {
                localStamps[name]?.let { stamps[name] = it }
            }
        }
        return StampedValue(value, stamps)
    }

    private fun <T> unknown(field: SyncField<T>, value: T, default: T): Long =
        if (field.read(value) != field.read(default)) UNKNOWN_CHANGE else 0L

    /**
     * The device to name beside a moment in the document.
     *
     * The previous document's device when the moment is the one it already carried, because
     * this device only took that change. Otherwise this device, which made it.
     */
    fun by(at: Long, previousAt: String?, previousBy: String?, device: String?): String? =
        if (previousBy != null && epochMillis(previousAt) == seconds(at)) previousBy else device

    /** The document's stamps as moments this device keeps. */
    fun moments(stamps: Map<String, DocumentStamp>): Map<String, Long> =
        stamps.mapNotNull { (name, stamp) -> epochMillis(stamp.at)?.let { name to it } }.toMap()

    /** Moments as the document writes them, each with the device that made it. */
    fun documentStamps(
        moments: Map<String, Long>,
        previous: Map<String, DocumentStamp>,
        device: String?,
    ): Map<String, DocumentStamp> = moments.toSortedMap().mapValues { (name, at) ->
        val before = previous[name]
        DocumentStamp(wireMoment(at), by(at, before?.at, before?.by, device))
    }
}
