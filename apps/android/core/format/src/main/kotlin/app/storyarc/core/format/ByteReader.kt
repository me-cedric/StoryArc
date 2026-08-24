package app.storyarc.core.format

/**
 * Little-endian reads over a byte array, bounds-checked.
 *
 * Every ZIP structure is little-endian. Bounds checks are not optional here:
 * this parser runs on untrusted input, and `SECURITY.md` names archive parsing
 * as the largest attack surface in the app. No length read out of a file is ever
 * used to allocate without being checked against the buffer first.
 *
 * iOS's `ByteReader` mirrors this file.
 */
internal class ByteReader(private val bytes: ByteArray, offset: Int = 0) {
    var cursor: Int = offset
        private set

    val remaining: Int get() = bytes.size - cursor

    fun seek(offset: Int) {
        require(offset in 0..bytes.size) { "seek out of range" }
        cursor = offset
    }

    fun skip(count: Int) {
        if (count < 0 || cursor + count > bytes.size) throw ZipException.Malformed("skip past end")
        cursor += count
    }

    fun uint16(): Int {
        val data = bytes(2)
        return (data[0].toInt() and 0xFF) or ((data[1].toInt() and 0xFF) shl 8)
    }

    fun uint32(): Long {
        val data = bytes(4)
        var value = 0L
        for (index in 3 downTo 0) {
            value = (value shl 8) or (data[index].toLong() and 0xFF)
        }
        return value
    }

    fun int64(): Long {
        val data = bytes(8)
        var value = 0L
        for (index in 7 downTo 0) {
            value = (value shl 8) or (data[index].toLong() and 0xFF)
        }
        return value
    }

    fun bytes(count: Int): ByteArray {
        if (count < 0 || cursor + count > bytes.size) throw ZipException.Malformed("read past end")
        val slice = bytes.copyOfRange(cursor, cursor + count)
        cursor += count
        return slice
    }

    /**
     * An entry name. ZIP stores UTF-8 when general-purpose bit 11 is set, and an
     * unspecified code page otherwise. Falling back to ISO-8859-1 keeps every
     * byte round-trippable rather than losing a name to a decode failure.
     */
    fun string(count: Int, isUtf8: Boolean): String {
        val raw = bytes(count)
        return if (isUtf8) raw.decodeToString() else String(raw, Charsets.ISO_8859_1)
    }
}
